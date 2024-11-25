#!/bin/bash

version=1.1.69

printf '#define CYDIA_VERSION "%s"\n' "$version" > Version.h
printf '%s\n' "$version"
