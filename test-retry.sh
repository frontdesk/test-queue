#!/bin/sh
set -x

export TEST_QUEUE_WORKERS=2 TEST_QUEUE_VERBOSE=1

bundle exec minitest-queue ./test/*_minispec.rb

echo "Re-running failed tests"
TEST_QUEUE_WORKERS=1 TEST_QUEUE_RERUN=1 bundle exec minitest-queue ./test/*_test.rb
