#!/usr/bin/env bash
#  Generate Rust bindings for Mynewt C API. Install "bindgen" before running:
#  cargo install bindgen
#  Also install rustfmt when prompted

set -e  #  Exit when any command fails.
set -x  #  Echo all commands.

function generate_bindings() {
    #  Generate bindings for the module.
    local libname=$1
    local modname=$2
    local libdir=$3
    # libcmd looks like bin/targets/bluepill_my_sensor/app/libs/sensor_network/libs/sensor_network/src/sensor_network.o.cmd
    local libcmd=$4
    shift 4
    local whitelist="$@"
    echo "whitelist=$whitelist"

    local expandcmd=logs/gen-bindings.txt
    local expandfile=logs/$modname-expanded.h

    #  Remove first line: arm-none-eabi-gcc
    tail +2 $libcmd \
        | sed "/^-o/,$ d" \
        > $expandcmd

    #  Append gcc options to expand macros. 
    cat \
        >> $expandcmd \
        << "EOF"
        -E 
        -dD
        -o
EOF

    #  Expand macros to sensor_network-expanded.h
    echo $expandfile >>$expandcmd

    #  Append the last line containing the source filename e.g. libs/sensor_network/src/sensor_network.c
    tail -1 \
        $libcmd \
        >> $expandcmd

    #  Run gcc to expand macros.
    arm-none-eabi-gcc @$expandcmd

    #  Generate Rust bindings for the expanded macros.
    bindgen \
        --use-core \
        --ctypes-prefix "::cty" \
        --with-derive-default \
        --no-derive-copy \
        --no-derive-debug \
        --no-layout-tests \
        $whitelist \
        -o src/mynewt/$modname.rs \
        $expandfile
}

function generate_bindings_kernel() {
    #  Generate bindings for kernel/$1 e.g. os.
    local libname=$1
    local modname=$1
    #  libdir looks like kernel/os
    local libdir=kernel/$libname
    #  libcmd looks like bin/targets/bluepill_my_sensor/app/kernel/os/repos/apache-mynewt-core/kernel/os/src/os.o.cmd
    local libcmd=bin/targets/bluepill_my_sensor/app/$libdir/repos/apache-mynewt-core/$libdir/src/$modname.o.cmd
    local whitelist=`cat << EOF
        --whitelist-var      (?i)SYS_E.* \
        --whitelist-function (?i)${modname}_.* \
        --whitelist-type     (?i)${modname}_.* \
        --whitelist-var      (?i)${modname}_.* 
EOF
`
    generate_bindings $libname $modname $libdir $libcmd $whitelist
}

function generate_bindings_apps() {
    #  Generate bindings for apps/$1 e.g. my_sensor_app.
    local libname=$1
    local modname=$2
    local libdir=apps/$libname
    local libcmd=bin/targets/bluepill_my_sensor/app/$libdir/$libdir/src/$modname.o.cmd
    local whitelist=
    generate_bindings $libname $modname $libdir $libcmd $whitelist
}

function generate_bindings_encoding() {
    #  Generate bindings for encoding/*
    #  libname: tinycbor, json
    local libname=$1
    local modname=$1
    #  srcname looks like cborencoder, json_encode
    local srcname=$2
    #  prefixname looks like cbor, json
    local prefixname=$3
    #  libdir looks like encoding/tinycbor, encoding/json_encode
    local libdir=encoding/$libname
    #  libcmd looks like 
    #  bin/targets/bluepill_my_sensor/app/encoding/tinycbor/repos/apache-mynewt-core/encoding/tinycbor/src/cborencoder.o.cmd
    #  bin/targets/bluepill_my_sensor/app/encoding/json/repos/apache-mynewt-core/encoding/json/src/json_encode.o.cmd
    local libcmd=bin/targets/bluepill_my_sensor/app/$libdir/repos/apache-mynewt-core/$libdir/src/$srcname.o.cmd
    if [ "$libname" == 'tinycbor' ]; then
        #  Skip incorrect binding "pub static CborIndefiniteLength: usize", replace by const:
        #  static const size_t CborIndefiniteLength = (0xffffffffU)
        local whitelist=`cat << EOF
            --raw-line pub \
            --raw-line const \
            --raw-line CborIndefiniteLength:usize=0xffffffffusize; \
            --blacklist-item     CborIndefiniteLength \
            --whitelist-function (?i)${prefixname}.* \
            --whitelist-type     (?i)${prefixname}.* \
            --whitelist-var      (?i)${prefixname}.* 
EOF
`
    else
        #  Add whitelist only.
        local whitelist=`cat << EOF
            --whitelist-function (?i)${prefixname}.* \
            --whitelist-type     (?i)${prefixname}.* \
            --whitelist-var      (?i)${prefixname}.* 
EOF
`
    fi
    generate_bindings $libname $modname $libdir $libcmd $whitelist
}

function generate_bindings_hw() {
    #  Generate bindings for hw/*
    #  libname: sensor
    local libname=$1
    local modname=$1
    #  srcname: sensor
    local srcname=$2
    #  prefixname: sensor
    local prefixname=$3
    #  libdir looks like hw/sensor
    local libdir=hw/$libname
    #  libcmd looks like 
    #  bin/targets/bluepill_my_sensor/app/hw/sensor/repos/apache-mynewt-core/hw/sensor/src/sensor.o.cmd
    local libcmd=bin/targets/bluepill_my_sensor/app/$libdir/repos/apache-mynewt-core/$libdir/src/$srcname.o.cmd
    #  Add whitelist only.
    local whitelist=`cat << EOF
        --whitelist-function (?i)${prefixname}.* \
        --whitelist-type     (?i)${prefixname}.* \
        --whitelist-var      (?i)${prefixname}.* 
EOF
`
    generate_bindings $libname $modname $libdir $libcmd $whitelist
}

function generate_bindings_libs() {
    #  Generate bindings for libs/*
    #  libname: sensor_network, sensor_coap
    local libname=$1
    local modname=$1
    #  srcname: sensor_network, sensor_coap
    local srcname=$2
    #  prefixname: sensor_network, sensor_coap
    local prefixname=$3    
    #  libdir looks like libs/sensor_network, libs/sensor_coap
    local libdir=libs/$libname
    #  libcmd looks like 
    #  bin/targets/bluepill_my_sensor/app/libs/sensor_network/libs/sensor_network/src/sensor_network.o.cmd
    #  bin/targets/bluepill_my_sensor/app/libs/sensor_coap/libs/sensor_coap/src/sensor_coap.o.cmd
    local libcmd=bin/targets/bluepill_my_sensor/app/$libdir/$libdir/src/$srcname.o.cmd
    if [ "$libname" == 'sensor_network' ]; then
        #  Add sensor network + whitelist.
        local whitelist=`cat << EOF
            --whitelist-function (?i)init_.*_post \
            --whitelist-function (?i)do_.*_post \
            --whitelist-function (?i)is_.*_node \
            --whitelist-function (?i)register_.*_transport \
            --whitelist-function (?i)should_send_to_.* \
            --whitelist-function (?i)get_device_id \
            --whitelist-function (?i)${prefixname}.* \
            --whitelist-type     (?i)${prefixname}.* \
            --whitelist-var      (?i)${prefixname}.* 
EOF
`
    elif [ "$libname" == 'sensor_coap' ]; then
        #  Add sensor coap + whitelist.
        local whitelist=`cat << EOF
            --whitelist-type     (?i)sensor_value \
            --whitelist-function (?i)init_sensor_.* \
            --whitelist-function (?i)sensor_coap_.* \
            --whitelist-function (?i)do_sensor_.* \
            --whitelist-function (?i)json_.* \
            --whitelist-var      (?i)coap_.* \
            --whitelist-function (?i)${prefixname}.*
EOF
`
    else
        #  Add whitelist only.
        local whitelist=`cat << EOF
            --whitelist-function (?i)${prefixname}.* \
            --whitelist-type     (?i)${prefixname}.* \
            --whitelist-var      (?i)${prefixname}.* 
EOF
`
    fi
    generate_bindings $libname $modname $libdir $libcmd $whitelist
}

# generate_bindings_encoding json     json_encode json  #  Generate bindings for encoding/json
# generate_bindings_encoding tinycbor cborencoder cbor  #  Generate bindings for encoding/tinycbor
# generate_bindings_kernel   os              #  Generate bindings for kernel/os
generate_bindings_hw sensor sensor sensor               #  Generate bindings for hw/sensor
generate_bindings_libs sensor_network sensor_network sensor_network #  Generate bindings for libs/sensor_network
generate_bindings_libs sensor_coap sensor_coap sensor_coap #  Generate bindings for libs/sensor_coap

# For testing only:
# generate_bindings_apps my_sensor_app send_coap  #  Generate bindings for my_sensor_app/send_coap.c

exit

→ bindgen --help
bindgen 0.49.2
Generates Rust bindings from C/C++ headers.

USAGE:
    bindgen [FLAGS] [OPTIONS] <header> -- <clang-args>...

FLAGS:
        --block-extern-crate                     Use extern crate instead of use for block.
        --builtins                               Output bindings for builtin definitions, e.g. __builtin_va_list.
        --conservative-inline-namespaces         Conservatively generate inline namespaces to avoid name conflicts.
        --disable-name-namespacing
            Disable namespacing via mangling, causing bindgen to generate names like "Baz" instead of "foo_bar_Baz" for
            an input name "foo::bar::Baz".
        --distrust-clang-mangling                Do not trust the libclang-provided mangling
        --dump-preprocessed-input
            Preprocess and dump the input header files to disk. Useful when debugging bindgen, using C-Reduce, or when
            filing issues. The resulting file will be named something like `__bindgen.i` or `__bindgen.ii`.
        --emit-clang-ast                         Output the Clang AST for debugging purposes.
        --emit-ir                                Output our internal IR for debugging purposes.
        --enable-cxx-namespaces                  Enable support for C++ namespaces.
        --enable-function-attribute-detection
            Enables detecting unexposed attributes in functions (slow).
                                   Used to generate #[must_use] annotations.
        --generate-block                         Generate block signatures instead of void pointers.
        --generate-inline-functions              Generate inline functions.
    -h, --help                                   Prints help information
        --ignore-functions
            Do not generate bindings for functions or methods. This is useful when you only care about struct layouts.

        --ignore-methods                         Do not generate bindings for methods.
        --impl-debug                             Create Debug implementation, if it can not be derived automatically.
        --impl-partialeq
            Create PartialEq implementation, if it can not be derived automatically.

        --no-convert-floats                      Do not automatically convert floats to f32/f64.
        --no-derive-copy                         Avoid deriving Copy on any type.
        --no-derive-debug                        Avoid deriving Debug on any type.
        --no-doc-comments
            Avoid including doc comments in the output, see: https://github.com/rust-lang/rust-bindgen/issues/426

        --no-include-path-detection              Do not try to detect default include paths
        --no-layout-tests                        Avoid generating layout tests for any type.
        --no-prepend-enum-name                   Do not prepend the enum name to bitfield or constant variants.
        --no-record-matches
            Do not record matching items in the regex sets. This disables reporting of unused items.

        --no-recursive-whitelist
            Disable whitelisting types recursively. This will cause bindgen to emit Rust code that won't compile! See
            the `bindgen::Builder::whitelist_recursively` method's documentation for details.
        --no-rustfmt-bindings                    Do not format the generated bindings with rustfmt.
        --objc-extern-crate                      Use extern crate instead of use for objc.
        --rustfmt-bindings
            Format the generated bindings with rustfmt. DEPRECATED: --rustfmt-bindings is now enabled by default.
            Disable with --no-rustfmt-bindings.
        --time-phases                            Time the different bindgen phases and print to stderr
        --unstable-rust                          Generate unstable Rust code (deprecated; use --rust-target instead).
        --use-array-pointers-in-arguments        Use `*const [T; size]` instead of `*const T` for C arrays
        --use-core                               Use types from Rust core instead of std.
        --use-msvc-mangling                      MSVC C++ ABI mangling. DEPRECATED: Has no effect.
    -V, --version                                Prints version information
        --verbose                                Print verbose error messages.
        --with-derive-default                    Derive Default on any type.
        --with-derive-eq
            Derive eq on any type. Enable this option also enables --with-derive-partialeq

        --with-derive-hash                       Derive hash on any type.
        --with-derive-ord
            Derive ord on any type. Enable this option also enables --with-derive-partialord

        --with-derive-partialeq                  Derive partialeq on any type.
        --with-derive-partialord                 Derive partialord on any type.

OPTIONS:
        --bitfield-enum <regex>...             Mark any enum whose name matches <regex> as a set of bitfield flags.
        --blacklist-function <function>...     Mark <function> as hidden.
        --blacklist-item <item>...             Mark <item> as hidden.
        --blacklist-type <type>...             Mark <type> as hidden.
        --constified-enum <regex>...           Mark any enum whose name matches <regex> as a series of constants.
        --constified-enum-module <regex>...    Mark any enum whose name matches <regex> as a module of constants.
        --ctypes-prefix <prefix>               Use the given prefix before raw types instead of ::std::os::raw.
        --default-enum-style <variant>         The default style of code used to generate enums. [default: consts]
                                               [possible values: consts, moduleconsts, bitfield, rust]
        --emit-ir-graphviz <path>              Dump graphviz dot file.
        --generate <generate>                  Generate only given items, split by commas. Valid values are
                                               "functions","types", "vars", "methods", "constructors" and "destructors".
        --no-copy <regex>...                   Avoid deriving Copy for types matching <regex>.
        --no-hash <regex>...                   Avoid deriving Hash for types matching <regex>.
        --no-partialeq <regex>...              Avoid deriving PartialEq for types matching <regex>.
        --opaque-type <type>...                Mark <type> as opaque.
    -o, --output <output>                      Write Rust bindings to <output>.
        --raw-line <raw-line>...               Add a raw line of Rust code at the beginning of output.
        --rust-target <rust-target>            Version of the Rust compiler to target. Valid options are: ["1.0",
                                               "1.19", "1.20", "1.21", "1.25", "1.26", "1.27", "1.28", "1.33",
                                               "nightly"]. Defaults to "1.33".
        --rustfmt-configuration-file <path>    The absolute path to the rustfmt configuration file. The configuration
                                               file will be used for formatting the bindings. This parameter is
                                               incompatible with --no-rustfmt-bindings.
        --rustified-enum <regex>...            Mark any enum whose name matches <regex> as a Rust enum.
        --whitelist-function <regex>...        Whitelist all the free-standing functions matching <regex>. Other non-
                                               whitelisted functions will not be generated.
        --whitelist-type <regex>...            Only generate types matching <regex>. Other non-whitelisted types will
                                               not be generated.
        --whitelist-var <regex>...             Whitelist all the free-standing variables matching <regex>. Other non-
                                               whitelisted variables will not be generated.

ARGS:
    <header>           C or C++ header file
    <clang-args>...
