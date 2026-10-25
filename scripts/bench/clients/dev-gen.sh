set -e
mkdir -p "$1"
cd "$1"
awk 'BEGIN {
    print "/* items.c, generated for the Hypoland benchmark */"
    print "#include <stdio.h>\n#include <stdlib.h>\n\nstruct item {\n    int count;\n    int *values;\n    const char *name;\n};\n"
    for (i = 1; i <= 14000; i++) {
        printf "/*\n * f%05d: adds up the values of an item that are %d modulo %d, takes v off the others\n */\n", i, i % 7, 7 + i % 5
        printf "static int f%05d(const struct item *it, int v) {\n    int sum = %d;\n\n", i, i % 101
        printf "    for (int i = 0; i < it->count; i++) {\n        if (it->values[i] %% %d == %d)\n", 7 + i % 5, i % 7
        printf "            sum += it->values[i] * %d;\n        else\n            sum -= v;\n    }\n", i % 13 + 2
        printf "    printf(\"%%s: f%05d %%d\\n\", it->name, sum);\n    return sum + %d;\n}\n\n", i, i % 997
    }
}' >a.c
awk '/^    return sum \+/ && ++n % 3 == 0 {sub(/;$/, " + 1;")} {print}' a.c >b.c
diff -u --color=always a.c b.c >dev.diff || true
# the user's git config stays out of it, a signing key or a hook would change what happens
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Dev GIT_AUTHOR_EMAIL=dev@example.org GIT_COMMITTER_NAME=Dev GIT_COMMITTER_EMAIL=dev@example.org
rm -rf repo
mkdir -p repo/src
cd repo
git init -q -b main
for i in $(seq 1 30); do
    head -n $((i * 3000)) ../a.c >src/items.c
    echo "items $i" >VERSION
    git add -A
    GIT_AUTHOR_DATE="@$((1767268800 + i * 3600)) +0000" GIT_COMMITTER_DATE="@$((1767268800 + i * 3600)) +0000" \
        git commit -q -m "items: add f$(((i - 1) * 200 + 1)) to f$((i * 200))"
done
# a change that is not committed, for git status and a git diff of 9000 lines
awk '/sum -= v;/ && ++n % 4 == 0 {sub(/v;/, "v + 1;")} {print}' ../a.c | head -n 90000 >src/items.c
