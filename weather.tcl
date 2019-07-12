#!/bin/sh
# the next line restarts using tclsh \
        exec tclsh "$0" "$@"

set resolvedArgv0 [file dirname [file normalize $argv0/___]];  # Trick to resolve last symlink
set appname [file rootname [file tail $resolvedArgv0]]
set rootdir [file normalize [file dirname $resolvedArgv0]]
foreach module [list toclbox] {
    foreach search [list lib/$module ../common/$module] {
        set dir [file join $rootdir $search]
        if { [file isdirectory $dir] } {
            ::tcl::tm::path add $dir
        }
    }
}
foreach search [list lib/modules] {
    set dir [file join $rootdir $search]
    if { [file isdirectory $dir] } {
        ::tcl::tm::path add $dir
    }
}
foreach module [list til] {
    foreach search [list lib/$module ../common/$module] {
        set dir [file join $rootdir $search]
        if { [file isdirectory $dir] } {
            lappend auto_path $dir
        }
    }
}

package require Tcl 8.6
package require toclbox
package require minihttpd
package require wapi::owm
package require wapi::darksky
package require wapi::weatherbit
set prg_args {
    -help       ""          "Print this help and exit"
    -verbose    "* DEBUG"   "Verbosity specification for program and modules"
    -owm        ""          "API key at openweathermap"
    -darksky    ""          "API key at DarkSky"
    -weatherbit ""          "API key at weatherbit.io"
    -lat        58.5356     "Latitude of location to serve data for"
    -lon        16.6244     "Longitude of location to serve data for"
    -period     "10M"       "Period for API requests"
    -http       "http:8080" "List of protocols and ports for HTTP servicing"
    -authorization ""       "HTTPd authorizations (pattern realm authlist)"
    -max        10          "Maximum lat,lon to cache"
}


# ::help:dump -- Dump help
#
#       Dump help based on the command-line option specification and
#       exit.
#
# Arguments:
#	hdr	Leading text to prepend to help message
#
# Results:
#       None.
#
# Side Effects:
#       Exit program
proc ::help:dump { { hdr "" } } {
    global appname
    
    if { $hdr ne "" } {
        puts $hdr
        puts ""
    }
    puts "NAME:"
    puts "\t$appname - Relays OpenWeatherMap data to SenML"
    puts ""
    puts "USAGE"
    puts "\t${appname}.tcl \[options\] -- \[controlled program\]"
    puts ""
    puts "OPTIONS:"
    foreach { arg val dsc } $::prg_args {
        puts "\t[string range ${arg}[string repeat \  15] 0 15]$dsc (default: ${val})"
    }
    exit
}
# Did we ask for help at the command-line, print out all command-line
# options described above and exit.
toclbox pullopt argv opts
if { [toclbox getopt opts -help] } {
    ::help:dump
}

# Extract list of command-line options into array that will contain
# program state.  The description array contains help messages, we get
# rid of them on the way into the main program's status array.
array set WEATHER {
    apis {}
}
foreach { arg val dsc } $prg_args {
    set WEATHER($arg) $val
}
for { set eaten "" } {$eaten ne $opts } {} {
    set eaten $opts
    foreach opt [array names WEATHER -*] {
        toclbox pushopt opts $opt WEATHER
    }
}
# Remaining args? Dump help and exit
if { [llength $opts] > 0 } {
    ::help:dump "[lindex $opts 0] is an unknown command-line option!"
}
# Setup program verbosity and arrange to print out how we were started if
# relevant.
toclbox verbosity {*}$WEATHER(-verbose)
set startup "Starting $appname with following options\n"
foreach {k v} [array get WEATHER -*] {
    append startup "\t[string range $k[string repeat \  10] 0 10]: $v\n"
}
toclbox debug DEBUG [string trim $startup]

proc HowLong {len unit} {
    if { [string is integer -strict $len] } {
        switch -glob -- $unit {
            "\[Yy\]*" {
                return [expr {$len*31536000}];   # Leap years?
            }
            "\[Mm\]\[Oo\]*" -
            "m*" {
                return [expr {$len*2592000}]
            }
            "\[Ww\]*" {
                return [expr {$len*604800}]
            }
            "\[Dd\]*" {
                return [expr {$len*86400}]
            }
            "\[Hh\]*" {
                return [expr {$len*3600}]
            }
            "\[Mm\]\[Ii\]*" -
            "M" {
                return [expr {$len*60}]
            }
            "\[Ss\]*" {
                return $len
            }
        }
    }
    return 0
}


proc Duration { str } {
    set words {}
    while {[scan $str %s%n word length] == 2} {
        lappend words $word
        set str [string range $str $length end]
    }

    set seconds 0
    for {set i 0} {$i<[llength $words]} {incr i} {
        set f [lindex $words $i]
        if { [scan $f %d%n n length] == 2 } {
            set unit [string range $f $length end]
            if { $unit eq "" } {
                incr seconds [HowLong $n [lindex $words [incr i]]]
            } else {
                incr seconds [HowLong $n $unit]
            }
        }
    }

    return $seconds
}

if { ! [string is integer -strict $WEATHER(-period)]} {
    toclbox debug NOTICE "Converting human-readable $WEATHER(-period)"
    set WEATHER(-period) [Duration $WEATHER(-period)]
}

toclbox https
foreach api [list owm darksky weatherbit] {
    if { $WEATHER(-$api) ne "" } {
        toclbox defaults ::wapi::$api -key $WEATHER(-$api) -max $WEATHER(-max)
        set impl [::wapi::${api}::new $WEATHER(-lat) $WEATHER(-lon)]
        lappend WEATHER(apis) $impl
    }
}
#htinit

vwait forever