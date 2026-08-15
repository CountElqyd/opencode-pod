#!/usr/bin/env bats

@test "[cli] destroy in config-less dir prints clean message (no unbound variable)" {
  local tmp
  tmp="$(mktemp -d)"

  run bash -c "cd '$tmp' && '$BATS_TEST_DIRNAME/../opencode-pod' destroy"

  [ "$status" -eq 1 ]
  [[ "$output" == *"No container found for this project."* ]]
  rm -rf "$tmp"
}

@test "[cli] status in config-less dir works" {
  local tmp
  tmp="$(mktemp -d)"

  run bash -c "cd '$tmp' && '$BATS_TEST_DIRNAME/../opencode-pod' status"

  [ "$status" -eq 0 ]
  [[ "$output" == *"State: nonexistent"* ]]
  rm -rf "$tmp"
}