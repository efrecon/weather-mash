package require Tcl 8.6
package require json
#package require toclbox
package require http

namespace eval ::wapi::darksky {
    namespace eval location {};  # Will host location contexts
    namespace eval gvars {
        variable -root     https://api.darksky.net/forecast
        variable -key      "";    # API key
        variable -max      -1;    # Max number of lat/lon
        variable -period   600;   # Update period in seconds
        variable -timeout  30000; # Timeout for HTTP operations
        variable service   "darksky"
    }
}


proc ::wapi::darksky::new { lat lon } {
    set api [search $lat $lon]
    if { $api ne "" } {
        return $api
    }

    Aging

    set api [toclbox identifier [namespace current]::location::]
    upvar \#0 $api API
    set API(-latitude) $lat
    set API(-longitude) $lon
    set API(-period) ${gvars::-period}
    set API(-key) ${gvars::-key}
    set API(-timeout) ${gvars::-timeout}
    set API(__creation) [clock milliseconds]
    foreach tgt [list acquired temperature pressure humidity wind_speed wind_direction] {
        set API($tgt) 0
    }

    Poller $api
    interp alias {} $api {} \
        ::toclbox::control::rdispatch $api [namespace current] \
        [list get delete]

    return $api
}


proc ::wapi::darksky::search { lat lon } {
    foreach api [info vars [namespace current]::location::*] {
        upvar \#0 $api API

        if { $lat == $API(-latitude) && $lon == $API(-longitude) } {
            return $api
        }
    }

    return ""
}


proc ::wapi::darksky::Aging {} {
    if { ${gvars::-max} > 0 } {
        set live [list]
        foreach api [info vars [namespace current]::location::*] {
            upvar \#0 $api API
            lappend live $api $API(__creation)
        }

        set live [lsort -index 1 -stride 2 -integer -decreasing $live]
        foreach {api creation} [lrange $live [expr {2*(${gvars::-max}-1)}] end] {
            upvar \#0 $api API
            toclbox debug NOTICE "$api ($API(-latitude),$API(-longitude)) created at\
                                  [clock format [expr {$API(__creation)/1000}]], too old. Removing!"
            delete $api
        }
    }
}


proc ::wapi::darksky::Poller { api } {
    if { ! [info exists $api] } {
        toclbox debug WARN "[dict get [info frame 0] proc]: $api does not exist"
        return
    }

    upvar \#0 $api API
    if { $API(-period) ne "" && $API(-period) >= 0 } {
        toclbox debug NOTICE "Next $gvars::service update in $API(-period) s."
        set API(__pulse) [after [expr {$API(-period)*1000}] [list [namespace current]::Poller $api]]
    }

    set API(__token) [::http::geturl ${gvars::-root}/$API(-key)/$API(-latitude),$API(-longitude),[clock seconds]?exclude=minutely,hourly,daily&units=si \
                                     -command [list [namespace current]::Store $api] \
                                     -timeout $API(-timeout)]
}


proc ::wapi::darksky::Store { api token } {
    if { ! [info exists $api] } {
        toclbox debug WARN "[dict get [info frame 0] proc]: $api does not exist"
        ::http::cleanup $token
        return
    }

    upvar \#0 $api API

    set API(__token) ""
    set ncode [::http::ncode $token]
    set data [::http::data $token]
    if { $ncode == 200 } {
        if { $data ne "" } {
            set json [::json::json2dict $data]
            set result [dict get $json currently]
            set mapper [list temperature temperature 1 \
                             pressure pressure 1 \
                             humidity humidity 100 \
                             windSpeed wind_speed 1 \
                             windBearing wind_direction 1]
            foreach { section tgt factor} $mapper {
                if { [dict exists $result $section] } {
                    set API($tgt) [expr {[dict get $result $section]*$factor}]
                    toclbox debug DEBUG "Current $tgt at $gvars::service is $API($tgt)"
                }
            }
            set API(acquired) [clock seconds]
        }
    } else {
        toclbox debug WARN "Could not call $gvars::service! code: $ncode, data: $data"
    }
    ::http::cleanup $token
}


proc ::wapi::darksky::get { api { tgt "" } } {
    if { ! [info exists $api] } {
        toclbox debug WARN "[dict get [info frame 0] proc]: $api does not exist"
        return
    }

    upvar \#0 $api API
    if { $tgt eq "" } {
        set answer [list]
        foreach k [array names API] {
            if { ![string match -* $k] && ![string match __* $k] } {
                lappend answer $k $API($k)
            }
        }
    } else {
        if { [array names API $tgt] ne "" ] } {
            return $API($tgt)
        }
    }

    return {}
}

proc ::wapi::darksky::delete { api } {
    if { ! [info exists $api] } {
        toclbox debug WARN "[dict get [info frame 0] proc]: $api does not exist"
        return
    }

    if { [info exists API(__pulse)] } {
        after cancel $API(__pulse)
    }
    if { [info exists API(__token)] && $API(__token) ne "" } {
        ::http::reset $API(__token) delete
    }
    unset $api
}


# If we are not being included in another script, run a quick test
if {[file normalize $::argv0] eq [file normalize [info script]]} {
    set rootdir [file normalize [file dirname $::argv0]]
    set tocldir [file join $rootdir .. .. toclbox]

    ::tcl::tm::path add $tocldir
    package require toclbox
    toclbox verbosity *darksky* DEBUG
    toclbox https
    set ::wapi::darksky::gvars::-max 1
    set ::wapi::darksky::gvars::-key [lindex $::argv 0]
    set svenstorp [::wapi::darksky::new 58.5356 16.6244]
    set second [::wapi::darksky::new 58.5356 16.6244]
    if { $svenstorp eq $second } {
        toclbox debug NOTICE "Getting back same object properly"
    }
    set london [::wapi::darksky::new 51.51 0.13]
    set svenstorp [::wapi::darksky::search 58.5356 16.6244]
    if { $svenstorp eq "" } {
        toclbox debug NOTICE "First created location has properly disappeared"
    }

    toclbox debug NOTICE "Dying in 1 minute"
    after 60000 exit
    vwait forever
}