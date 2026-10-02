#!/bin/bash
# about: the runner's own check: hangs on purpose (with a child process) to show the limit and cleanup work.
# limit: 3
sleep 300 & echo "child $!"; sleep 300
