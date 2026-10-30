#include "Shm.hpp"
#include <algorithm>
#include <sys/mman.h>
#include <sys/stat.h>
#include <drm_fourcc.h>
#include "../../render/Texture.hpp"
#include "../types/WLBuffer.hpp"
#include "../../helpers/Format.hpp"
#include "../../render/Renderer.hpp"
#include <hyprgraphics/egl/Egl.hpp>
#include <fcntl.h>
#include <unistd.h>
#include <cerrno>
#include <cstring>
#include <print>
#include <sys/ioctl.h>
#include <linux/udmabuf.h>
#include <i915_drm.h>
#if defined(__x86_64__) || defined(__i386__)
#include <immintrin.h>
#endif
#include "../../Compositor.hpp"
#include "../../render/OpenGL.hpp"

using namespace Hyprgraphics::Egl;
using namespace Hyprutils::OS;

// Zero copy for shm clients (2026-10-29, on by default where the gate below allows it; HYPOLAND_SHM_ZEROCOPY=0 switches it
// off, "force" ignores the gate): a wl_buffer whose pool is a memfd
// sealed against shrinking gets a udmabuf of its pages (/dev/udmabuf), imported as a linear EGLImage, so the GPU samples
// the client's memory and the compositor copies nothing. Such a buffer is asynchronous like a dmabuf: the surface keeps it
// until the next one arrives, the renderer until the frame that read it is done, and only then is it released to the
// client. The client's writes reach the GPU without a cache flush only where GPU reads snoop the CPU caches: Intel with
// an LLC (iris everywhere, crocus from Sandy Bridge) and radeon. On Intel without an LLC (GM45, Bay Trail) the GPU
// reads memory, so there the compositor writes the client's damaged cache lines back itself at every commit (clflush,
// x86 only; without it the screen shows specks of old glyphs): still far cheaper than a copy (Chromebook
// terminal-scroll 7.2 -> 5.5% of a CPU, Qt's software scroll 12.9 -> 4.1, 2026-10-29). "force" takes every driver
// without a flush, "flush" every driver with one.
static bool s_flushWrites = false;
static bool zeroCopyAllowed() {
    static int allowed = -1;
    if (allowed >= 0)
        return allowed;
    allowed         = 0;
    const char* ENV = std::getenv("HYPOLAND_SHM_ZEROCOPY");
    if (ENV && (std::string_view{ENV} == "0" || std::string_view{ENV} == "off"))
        return false;
    if (!ENV)
        ENV = "";
    const auto& DRIVER = Render::GL::g_pHyprOpenGL->m_eglDriverName;
    std::string why    = DRIVER;
    if (std::string_view{ENV} == "force") {
        allowed = 1;
        why += ", forced";
    } else if (std::string_view{ENV} == "flush") {
#if defined(__x86_64__) || defined(__i386__)
        allowed       = 1;
        s_flushWrites = true;
        why += ", the compositor flushes the caches";
#else
        why += ", no cache flush on this architecture";
#endif
    } else if (DRIVER == "iris" || DRIVER == "crocus") {
        int                 llc = 0;
        drm_i915_getparam_t gp  = {.param = I915_PARAM_HAS_LLC, .value = &llc};
        if (g_pCompositor->m_drm.fd >= 0 && ioctl(g_pCompositor->m_drm.fd, DRM_IOCTL_I915_GETPARAM, &gp) == 0 && llc) {
            allowed = 1;
            why += ", LLC";
        } else {
#if defined(__x86_64__) || defined(__i386__)
            // GM45, Bay Trail: the GPU reads memory, so the compositor writes the client's lines back itself
            allowed       = 1;
            s_flushWrites = true;
            why += " without an LLC, the compositor flushes the caches";
#else
            why += " without an LLC";
#endif
        }
    } else if (DRIVER == "r600" || DRIVER == "radeonsi")
        allowed = 1;
    else
        why += ", not known to read CPU writes coherently";
    std::println(stderr, "shm zero copy: {} ({})", allowed ? "on" : "off", why);
    return allowed;
}

static int udmabufDevice() {
    static CFileDescriptor dev;
    static bool            tried = false;
    if (!tried) {
        tried = true;
        dev   = CFileDescriptor{open("/dev/udmabuf", O_RDWR | O_CLOEXEC)};
        if (!dev.isValid())
            std::println(stderr, "shm zero copy: cannot open /dev/udmabuf: {}", strerror(errno));
    }
    return dev.isValid() ? dev.get() : -1;
}

CWLSHMBuffer::CWLSHMBuffer(WP<CWLSHMPoolResource> pool_, uint32_t id, int32_t offset_, const Vector2D& size_, int32_t stride_, uint32_t fmt_) {
    if UNLIKELY (!pool_)
        return;

    if UNLIKELY (!pool_->m_pool || pool_->m_pool->m_data == MAP_FAILED)
        return;

    size     = size_;
    m_pool   = pool_->m_pool;
    m_stride = stride_;
    m_fmt    = fmt_;
    m_offset = offset_;
    m_opaque = isDrmFormatOpaque(NFormatUtils::shmToDRM(fmt_));

    m_resource = CWLBufferResource::create(makeShared<CWlBuffer>(pool_->m_resource->client(), 1, id));

    m_listeners.bufferResourceDestroy = events.destroy.listen([this] {
        m_listeners.bufferResourceDestroy.reset();
        PROTO::shm->destroyResource(this);
    });

    m_zeroCopy = tryZeroCopy();
}

CWLSHMBuffer::~CWLSHMBuffer() {
    if (m_resource)
        m_resource->sendRelease();
}

Aquamarine::eBufferCapability CWLSHMBuffer::caps() {
    return Aquamarine::eBufferCapability::BUFFER_CAPABILITY_DATAPTR;
}

Aquamarine::eBufferType CWLSHMBuffer::type() {
    return Aquamarine::eBufferType::BUFFER_TYPE_SHM;
}

void CWLSHMBuffer::flushCPUWrites(const CRegion& bufferDamage) {
#if defined(__x86_64__) || defined(__i386__)
    if (!m_zeroCopy || !s_flushWrites || !m_pool || !m_pool->m_data)
        return;

    const auto BASE = rc<uint8_t*>(m_pool->m_data) + m_offset;
    bufferDamage.copy().intersect(CBox{{}, size}).forEachRect([&](const auto& RECT) {
        for (int y = RECT.y1; y < RECT.y2; y++) {
            const auto ROW = BASE + sc<size_t>(y) * m_stride;
            const auto END = ROW + sc<size_t>(RECT.x2) * 4;
            for (auto p = rc<uintptr_t>(ROW + sc<size_t>(RECT.x1) * 4) & ~sc<uintptr_t>(63); p < rc<uintptr_t>(END); p += 64)
                _mm_clflush(rc<const void*>(p));
        }
    });
    _mm_mfence();
#endif
}

bool CWLSHMBuffer::needsCPUFlush() {
    return m_zeroCopy && s_flushWrites && m_pool && m_pool->m_data;
}

bool CWLSHMBuffer::isSynchronous() {
    return !m_zeroCopy;
}

Aquamarine::SSHMAttrs CWLSHMBuffer::shm() {
    Aquamarine::SSHMAttrs attrs;
    attrs.success = true;
    attrs.fd      = m_pool->m_fd.get();
    attrs.format  = NFormatUtils::shmToDRM(m_fmt);
    attrs.size    = size;
    attrs.stride  = m_stride;
    attrs.offset  = m_offset;
    return attrs;
}

Aquamarine::SDMABUFAttrs CWLSHMBuffer::dmabuf() {
    return m_zeroCopy ? m_dmabufAttrs : Aquamarine::SDMABUFAttrs{};
}

bool CWLSHMBuffer::tryZeroCopy() {
    if (!zeroCopyAllowed())
        return false;

    const auto DRMFMT = NFormatUtils::shmToDRM(m_fmt);
    if (DRMFMT != DRM_FORMAT_ARGB8888 && DRMFMT != DRM_FORMAT_XRGB8888)
        return false;

    // a udmabuf needs a memfd that cannot shrink under it: foot, Chromium, GTK 4 and Qt seal their pools so, GTK 3 does not
    const int SEALS = fcntl(m_pool->m_fd.get(), F_GET_SEALS);
    if (SEALS < 0 || !(SEALS & F_SEAL_SHRINK))
        return false;

    const int DEV = udmabufDevice();
    if (DEV < 0)
        return false;

    static const size_t PAGE  = sc<size_t>(sysconf(_SC_PAGESIZE));
    const size_t        START = sc<size_t>(m_offset) & ~(PAGE - 1);
    const size_t        END   = (sc<size_t>(m_offset) + sc<size_t>(m_stride) * sc<size_t>(size.y) + PAGE - 1) & ~(PAGE - 1);
    struct stat         st;
    if (fstat(m_pool->m_fd.get(), &st) < 0 || END > sc<size_t>(st.st_size))
        return false; // the last page would reach past the file

    udmabuf_create create = {.memfd = sc<uint32_t>(m_pool->m_fd.get()), .flags = UDMABUF_FLAGS_CLOEXEC, .offset = START, .size = END - START};
    m_dmabufFd            = CFileDescriptor{ioctl(DEV, UDMABUF_CREATE, &create)};
    if (!m_dmabufFd.isValid()) {
        static bool once = true;
        if (once)
            std::println(stderr, "shm zero copy: no udmabuf of {} bytes: {}", END - START, strerror(errno));
        once = false;
        return false;
    }

    m_dmabufAttrs            = {.success = true, .size = size, .format = DRMFMT, .modifier = DRM_FORMAT_MOD_LINEAR, .planes = 1};
    m_dmabufAttrs.offsets[0] = sc<uint32_t>(sc<size_t>(m_offset) - START);
    m_dmabufAttrs.strides[0] = sc<uint32_t>(m_stride);
    m_dmabufAttrs.fds[0]     = m_dmabufFd.get();

    m_texture = g_pHyprRenderer->createTexture(m_dmabufAttrs, m_opaque);
    if (!m_texture || !m_texture->ok()) {
        static bool once = true;
        if (once)
            std::println(stderr, "shm zero copy: EGL import of a {}x{} udmabuf failed", sc<int>(size.x), sc<int>(size.y));
        once = false;
        m_texture.reset();
        m_dmabufFd.reset();
        m_dmabufAttrs = {};
        return false;
    }

    static bool said = false;
    if (!said)
        std::println(stderr, "shm zero copy: client buffers sampled in place");
    said = true;
    return true;
}

std::tuple<uint8_t*, uint32_t, size_t> CWLSHMBuffer::beginDataPtr(uint32_t flags) {
    return {sc<uint8_t*>(m_pool->m_data) + m_offset, m_fmt, sc<size_t>(m_stride) * sc<size_t>(size.y)};
}

void CWLSHMBuffer::endDataPtr() {
    ;
}

bool CWLSHMBuffer::good() {
    return m_resource && m_resource->good() && m_pool && m_pool->m_data != MAP_FAILED;
}

void CWLSHMBuffer::update(const CRegion& damage) {
    ;
}

CSHMPool::CSHMPool(CFileDescriptor fd_, size_t size_) : m_fd(std::move(fd_)), m_size(size_), m_data(mmap(nullptr, m_size, PROT_READ | PROT_WRITE, MAP_SHARED, m_fd.get(), 0)) {
    ;
}

CSHMPool::~CSHMPool() {
    if (m_data != MAP_FAILED)
        munmap(m_data, m_size);
}

void CSHMPool::resize(size_t size_) {
    LOGM(Log::DEBUG, "Resizing a SHM pool from {} to {}", m_size, size_);

    if (m_data != MAP_FAILED)
        munmap(m_data, m_size);

    m_size = size_;
    m_data = mmap(nullptr, m_size, PROT_READ | PROT_WRITE, MAP_SHARED, m_fd.get(), 0);

    if UNLIKELY (m_data == MAP_FAILED)
        LOGM(Log::ERR, "Couldn't mmap {} bytes from fd {} of shm client", m_size, m_fd.get());
}

static int shmIsSizeValid(CFileDescriptor& fd, int32_t size) {
    if UNLIKELY (size <= 0)
        return 0;

    struct stat st;
    if UNLIKELY (fstat(fd.get(), &st) == -1) {
        LOGM(Log::ERR, "Couldn't get stat for fd {} of shm client", fd.get());
        return 0;
    }

    return sc<size_t>(st.st_size) >= sc<size_t>(size);
}

CWLSHMPoolResource::CWLSHMPoolResource(UP<CWlShmPool>&& resource_, CFileDescriptor fd_, size_t size_) : m_resource(std::move(resource_)) {
    if UNLIKELY (!good())
        return;

    m_pool = makeShared<CSHMPool>(std::move(fd_), size_);

    m_resource->setDestroy([this](CWlShmPool* r) { PROTO::shm->destroyResource(this); });
    m_resource->setOnDestroy([this](CWlShmPool* r) { PROTO::shm->destroyResource(this); });

    m_resource->setResize([this](CWlShmPool* r, int32_t size_) {
        if UNLIKELY (size_ < sc<int32_t>(m_pool->m_size)) {
            r->error(WL_SHM_ERROR_INVALID_FD, "Shrinking a shm pool is illegal");
            return;
        }
        if UNLIKELY (!shmIsSizeValid(m_pool->m_fd, size_)) {
            r->error(WL_SHM_ERROR_INVALID_STRIDE, "The pool size is invalid or the file is not big enough for it");
            return;
        }

        m_pool->resize(size_);
    });

    m_resource->setCreateBuffer([this](CWlShmPool* r, uint32_t id, int32_t offset, int32_t w, int32_t h, int32_t stride, uint32_t fmt) {
        if UNLIKELY (!m_pool || m_pool->m_data == MAP_FAILED) {
            r->error(WL_SHM_ERROR_INVALID_FD, "The provided shm pool failed to allocate properly");
            return;
        }

        if UNLIKELY (std::ranges::find(PROTO::shm->m_shmFormats, fmt) == PROTO::shm->m_shmFormats.end()) {
            r->error(WL_SHM_ERROR_INVALID_FORMAT, "Format invalid");
            return;
        }

        if UNLIKELY (offset < 0 || w <= 0 || h <= 0 || stride <= 0) {
            r->error(WL_SHM_ERROR_INVALID_STRIDE, "Invalid stride, w, h, or offset");
            return;
        }

        if UNLIKELY (!NFormatUtils::isShmBufferLayoutValid(NFormatUtils::shmToDRM(fmt), {w, h}, stride, offset, m_pool->m_size)) {
            r->error(WL_SHM_ERROR_INVALID_STRIDE, "Buffer would exceed pool size or has an invalid stride");
            return;
        }

        const auto& RESOURCE = PROTO::shm->m_buffers.emplace_back(makeShared<CWLSHMBuffer>(m_self, id, offset, Vector2D{w, h}, stride, fmt));

        if UNLIKELY (!RESOURCE->good()) {
            r->noMemory();
            PROTO::shm->m_buffers.pop_back();
            return;
        }

        // append instance so that buffer knows its owner
        RESOURCE->m_resource->m_buffer = RESOURCE;
    });

    if UNLIKELY (m_pool->m_data == MAP_FAILED)
        m_resource->error(WL_SHM_ERROR_INVALID_FD, "Couldn't mmap from fd");
}

bool CWLSHMPoolResource::good() {
    return m_resource->resource();
}

CWLSHMResource::CWLSHMResource(UP<CWlShm>&& resource_) : m_resource(std::move(resource_)) {
    if UNLIKELY (!good())
        return;

    m_resource->setRelease([this](CWlShm* r) { PROTO::shm->destroyResource(this); });
    m_resource->setOnDestroy([this](CWlShm* r) { PROTO::shm->destroyResource(this); });

    m_resource->setCreatePool([](CWlShm* r, uint32_t id, int32_t fd, int32_t size) {
        CFileDescriptor poolFd{fd};

        // validate size and backing file before creating the pool resource, so a rejected pool is never added to m_pools
        if UNLIKELY (!shmIsSizeValid(poolFd, size)) {
            r->error(WL_SHM_ERROR_INVALID_STRIDE, "The pool size is invalid or the file is not big enough for it");
            return;
        }

        const auto& RESOURCE = PROTO::shm->m_pools.emplace_back(makeUnique<CWLSHMPoolResource>(makeUnique<CWlShmPool>(r->client(), r->version(), id), std::move(poolFd), size));

        if UNLIKELY (!RESOURCE->good()) {
            r->noMemory();
            PROTO::shm->m_pools.pop_back();
            return;
        }

        RESOURCE->m_self = RESOURCE;
    });

    // send a few supported formats. No need for any other I think?
    for (auto const& s : PROTO::shm->m_shmFormats) {
        m_resource->sendFormat(sc<wl_shm_format>(s));
    }
}

bool CWLSHMResource::good() {
    return m_resource->resource();
}

CWLSHMProtocol::CWLSHMProtocol(const wl_interface* iface, const int& ver, const std::string& name) : IWaylandProtocol(iface, ver, name) {
    ;
}

void CWLSHMProtocol::bindManager(wl_client* client, void* data, uint32_t ver, uint32_t id) {
    if (m_shmFormats.empty()) {
        m_shmFormats.push_back(WL_SHM_FORMAT_ARGB8888);
        m_shmFormats.push_back(WL_SHM_FORMAT_XRGB8888);

        static const std::array<DRMFormat, 6> supportedShmFourccFormats = {
            DRM_FORMAT_XBGR8888, DRM_FORMAT_ABGR8888, DRM_FORMAT_XRGB2101010, DRM_FORMAT_ARGB2101010, DRM_FORMAT_XBGR2101010, DRM_FORMAT_ABGR2101010,
        };

        for (auto const& fmt : supportedShmFourccFormats) {
            m_shmFormats.push_back(fmt);
        }
    }

    const auto& RESOURCE = m_managers.emplace_back(makeUnique<CWLSHMResource>(makeUnique<CWlShm>(client, ver, id)));

    if UNLIKELY (!RESOURCE->good()) {
        wl_client_post_no_memory(client);
        m_managers.pop_back();
        return;
    }
}

void CWLSHMProtocol::destroyResource(CWLSHMResource* resource) {
    std::erase_if(m_managers, [&](const auto& other) { return other.get() == resource; });
}

void CWLSHMProtocol::destroyResource(CWLSHMPoolResource* resource) {
    std::erase_if(m_pools, [&](const auto& other) { return other.get() == resource; });
}

void CWLSHMProtocol::destroyResource(CWLSHMBuffer* resource) {
    std::erase_if(m_buffers, [&](const auto& other) { return other.get() == resource; });
}
