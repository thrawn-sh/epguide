#!/bin/sh

export PERLLIB=$PERLLIB:`dirname $0`/lib
./bin/epguide-notify $@
