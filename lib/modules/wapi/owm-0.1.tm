package require Tcl 8.6
package require json
package require toclbox
package require http

namespace eval ::wapi::owm {
    namespace eval location {};  # Will host location contexts
    namespace eval gvars {
        variable generator 0;     # Generator for identifiers
        variable -root     https://api.openweathermap.org/data/2.5/weather
        variable -key      "";    # API key
        variable -max      10;    # Max number of lat/lon
        variable -period   600;   # Update period in seconds
        variable -timeout  30000; # Timeout for HTTP operations
    }
}


proc ::wapi::owm::new { lat lon } {
    set api [search $lat $lon]
    if { $api ne "" } {
        return $api
    }

    set api [namespace current]::location::[format %05d [incr gvars::generator]]
    upvar \#0 $api API
    set API(-latitude) $lat
    set API(-longitude) $lon
    set API(-period) ${gvars::-period}
    set API(-key) ${gvars::-key}
    set API(-timeout) ${gvars::-timeout}
    foreach tgt [list temperature pressure humidity wind_speed wind_direction] {
        set API($tgt) 0
    }

    Poller $api
    interp alias {} $api {} \
        ::toclbox::control::rdispatch $api [namespace current] \
        [list get delete]

    return $api
}


proc ::wapi::owm::search { lat lon } {
    foreach api [info vars [namespace current]::location::*] {
        upvar \#0 $api API

        if { $lat == $API(-latitude) && $lon == $API(-longitude) } {
            return $api
        }
    }

    return ""
}


proc ::wapi::owm::Poller { api } {
    if { ! [info exists $api] } {
        toclbox debug WARN "$api does not exist"
        return
    }

    upvar \#0 $api API
    if { $API(-period) ne "" && $API(-period) >= 0 } {
        toclbox debug NOTICE "Next OWM update in $API(-period) s."
        set API(__pulse) [after [expr {$API(-period)*1000}] [list [namespace current]::Poller $api]]
    }

    set API(__token) [::http::geturl ${gvars::-root}?APPID=$API(-key)&units=metric&lat=$API(-latitude)&lon=$API(-longitude) \
                                     -command [list [namespace current]::Store $api] \
                                     -timeout $API(-timeout)]
}


proc ::wapi::owm::Store { api token } {
    if { ! [info exists $api] } {
        toclbox debug WARN "$api does not exist"
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
            set mapper [list main temp temperature \
                             main pressure pressure \
                             main humidity humidity \
                             wind speed wind_speed \
                             wind deg wind_direction]
            foreach { section subsection tgt } $mapper {
                if { [dict exists $json $section] && [dict exists $json $section $subsection] } {
                    set API($tgt) [dict get $json $section $subsection]
                    toclbox debug DEBUG "Current $tgt is $API($tgt)"
                }
            }
        }
    } else {
        toclbox debug WARN "Could not call openweathermap! code: $ncode, data: $data"
    }
    ::http::cleanup $token
}


proc ::wapi::owm::get { api { tgt "" } } {
    if { ! [info exists $api] } {
        toclbox debug WARN "$api does not exist"
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

proc ::wapi::owm::delete { api } {
    if { ! [info exists $api] } {
        toclbox debug WARN "$api does not exist"
        return
    }

    after cancel $API(__pulse)
    if { $API(__token) ne "" } {
        ::http::reset $API(__token) delete
    }
    unset $api
}
