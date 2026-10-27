#include "../shared.hpp"
#include "../../shared.hpp"
#include "../../hyprctlCompat.hpp"
#include "tests.hpp"

TEST_CASE(layoutCustomGrid) {
    OK(getFromSocket("r/eval hl.config({ general = { layout = 'lua:grid' } })"));

    SPAWN_FOOT("foot_A");
    SPAWN_FOOT("foot_B");

    {
        auto clients = getFromSocket("/clients");
        EXPECT_COUNT_STRING(clients, "size: 931,1036", 2);
    }

    SPAWN_FOOT("foot_C");

    {
        auto clients = getFromSocket("/clients");
        EXPECT_COUNT_STRING(clients, "size: 931,511", 3);
    }

    SPAWN_FOOT("foot_D");

    {
        auto clients = getFromSocket("/clients");
        EXPECT_COUNT_STRING(clients, "size: 931,511", 4);
    }
}

TEST_CASE(layoutCustomColumns) {
    OK(getFromSocket("r/eval hl.config({ general = { layout = 'lua:columns' } })"));

    SPAWN_FOOT("foot_A");
    SPAWN_FOOT("foot_B");

    {
        auto clients = getFromSocket("/clients");
        EXPECT_COUNT_STRING(clients, "size: 931,1036", 2);
    }

    SPAWN_FOOT("foot_C");

    {
        auto clients = getFromSocket("/clients");
        EXPECT_COUNT_STRING(clients, ",1036\n", 3); // this won't split evenly
    }

    SPAWN_FOOT("foot_D");

    {
        auto clients = getFromSocket("/clients");
        EXPECT_COUNT_STRING(clients, ",1036\n", 4); // this won't split evenly
    }
}
