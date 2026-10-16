#!/bin/sh
# run_suite.sh [core|chip] [CACHE=1] - the SDCC test suite's self-checking
# programs (lisa-tools/sdcc_test/*.ihx) on the core-level or the chip-level
# testbench; one line per program, PASS/FAIL.
where=${1:-chip}
shift
SDCC_TEST=${SDCC_TEST:-$(dirname "$0")/../../lisa-tools/sdcc_test}
SELFCHECK="test_core test_negate test_union test_varargs test_digits test_signed test_strs test_regress test_pfu test_loop test_bigframe test_irq test_irq2 test_divsh test_divl test_bf16 test_bf16f test_ptroff test_rot test_index test_vshift"
CACHE_TESTS="test_cacherm test_cachermw test_cachepush test_cachewb test_cacheseq test_cacheloop test_cacheperiph"
case "$*" in *CACHE=1*) list="$CACHE_TESTS test_ptroff test_bigframe";; *) list="$SELFCHECK";; esac
dir=$(dirname "$0"); [ "$where" = core ] && dir="$dir/core"
pass=0; fail=0
for t in $list; do
  out=$(cd "$dir" && make IHX="$SDCC_TEST/$t.ihx" TIMEOUT=${TIMEOUT:-6000000} "$@" 2>&1)
  if printf '%s' "$out" | grep -q "test_program *PASS"; then
    echo "PASS $t"; pass=$((pass+1))
  else
    echo "FAIL $t"; printf '%s\n' "$out" | grep "LISA\] \(FAIL\|SOME\)\|Timeout\|rror" | head -5; fail=$((fail+1))
  fi
done
echo "$pass passed, $fail failed ($where $*)"
