#######################################################################################################################
### A Decent DE1app extension for sending profiles to, and reading shots from, pyDE1.
###  
### Source code available in GitHub: https://github.com/ebengoechea/de1app_plugin_pyde1/
### This code is released under GPLv3 license. See LICENSE file under the DE1 source folder in github.
###
### By Enrique Bengoechea <enri.bengoechea@gmail.com> 
########################################################################################################################
#set ::skindebug 1
plugins enable pyde1
#fconfigure $::logging::_log_fh -buffering line
#dui config debug_buttons 1

package require http
package require tls
package require json
package require rest

namespace eval ::plugins::pyde1 {
	variable author "Enrique Bengoechea"
	variable contact "enri.bengoechea@gmail.com"
	variable version 0.1
	variable github_repo ebengoechea/de1app_plugin_pyde1
	variable name "pyDE1"
	variable description [translate "Communicate with pyDE1."]

	variable min_de1app_version {1.37}
	variable connected 0

	variable last_request {}
	variable last_request_timestamp {}
	variable last_request_success 0
	variable last_request_result {}
	
	# References to GUI widgets 
	variable widgets
	array set widgets {}
}

### PLUGIN WORKFLOW ###################################################################################################

# Startup the Describe Your Espresso plugin.
proc ::plugins::pyde1::main {} {
	variable settings
	msg "Starting the pyDE1 plugin"
	check_versions

	# TODO: Add GUI integration to the skin
	
	# Upload a JSON profile from disk for storage. Need to take it from a file as on the spot conversion to JSON not yet supported 
#	set profileTitle "Backflush cleaning"
#	set profileFile "[homedir]/profiles_v2/${profileTitle}.json"
	#set upload_result [request de1/profile/store PUT [read_binary_file $profileFile]]
	
	
}

# Paint settings screen
proc ::plugins::pyde1::preload {} {
	package require de1_logging 1.0
	package require de1_dui 1.0
	
	check_settings
	plugins save_settings pyde1
	
#	setup_default_aspects
	dui page add pyde1_settings -namespace ::plugins::pyde1::pyde1_settings -theme default -type fpdialog
	return pyde1_settings
}


# Verify the minimum required versions of DE1 app & skin are used, and that required plugins are availabe and installed,
#	otherwise prevents startup.
proc ::plugins::pyde1::check_versions {} {
	if { [package vcompare [package version de1app] $::plugins::DYE::min_de1app_version] < 0 } {
		message_page "[translate {Plugin 'pyDE1'}] v$::plugins::DYE::plugin_version [translate requires] \
DE1app v$::plugins::DYE::min_de1app_version [translate {or higher}]\r\r[translate {Current DE1app version is}] [package version de1app]" \
		[translate Ok]
	}
}

# Ensure all settings values are defined, otherwise set them to their default values.
proc ::plugins::pyde1::check_settings {} {
	variable settings
	
	set settings(version) $::plugins::pyde1::version
	
	ifexists settings(hostname) raspberrypi.local
	ifexists settings(port) 1234
	ifexists settings(use_https) 1
	ifexists settings(n_sync_shots) 10
}


# Defines the pyde1-specific aspect styles for the default theme. These are always needed even if the current theme used is 
# another one, to have a default and to build the settings page with the default theme.
proc ::plugins::pyde1::setup_default_aspects { args } {
	set theme default
	
}

proc ::plugins::pyde1::reset_last_request { {request {}} } {
	variable last_request
	variable last_request_timestamp
	variable last_request_success
	variable last_request_result
	
	set last_request $last_request
	set last_request_timestamp [clock seconds]
	set last_request_success 0
	set last_request_result {}
}

# Using rest package 
proc ::plugins::pyde1::rest { endpoint {query {}} {config {}} {body {}} } {
	variable settings
	if { $endpoint eq "" } {
		msg -WARN [namespace current] get: "'endpoint' not specified"
		return
	}	
	
	if { [string is true $settings(use_https)] } {
		set url "https://"
	} else {
		set url "http://"
	}
	append url "$settings(hostname):$settings(port)/$endpoint"

	if { $config eq {} } {
		set config {method get format json}
	}
	
	set response ""
	try {
		set response [::rest::get $url $query $config $body]
		set response [::rest::format_json $response]
	} on error err {
		msg -WARNING [namespace current] rest: "Error on REST request $url: $err"
		dui say [translate "Request to pyDE1 failed"]
		#message_page "Error on REST request $url: $err" [translate Ok]
	}
	
	msg -INFO [namespace current] rest: "$url => $response"
	return $response
}

# Using http package gives finer control than using the rest package.
# If successful, returns a dictionary with the parsed JSON response. If it fails, returns an empty string.
proc ::plugins::pyde1::request { endpoint {method GET} {query {}} {headers {}} {body {}} } {
	variable settings
	reset_last_request
	variable last_request_success
	variable last_request_result
	
	if { $endpoint eq "" } {
		set last_request_result "'endpoint' not specified"
		msg -WARNING [namespace current] request: $last_request_result
		return
	}	
	if { $method ni {GET PUT PATCH} } {
		set last_request_result "'method' has to be one of GET, PUT or PATCH"
		msg -WARNING [namespace current] request: $last_request_result
		return
	}
	
	if { [string is true $settings(use_https)] } {
		set url "https://"
	} else {
		set url "http://"
	}
	append url "$settings(hostname):$settings(port)/$endpoint"
	
	try {
		#::http::register https 443 [::tls::socket $settings(hostname) $settings(port)]
		::http::register https 443 ::tls::socket
	} on error err {
		set last_request_result "Can't register $settings(hostname):$settings(port) - $err: $err"
		msg -ERROR [namespace current] request: $last_request_result
		dui say [translate "Request to pyDE1 failed"]
		
		#message_page "Can't register $settings(hostname):$settings(port) - $err" [translate Ok]
		return
	}
	
	set status ""
	set answer ""
	set code ""
	set ncode ""
	set response ""
	
	# NOTE: Curl profile upload uses headers: Accept */* Content-Type application/x-www-form-urlencoded and Content-Length with the size.
	#	Doesn't seem required, though.
	# msg -INFO [namespace current] main: "PROFILE length: [string length $profileFile]"		
	try {
		set token [::http::geturl $url -method $method -type "application/json" -query $query -timeout 10000]
		set status [::http::status $token]
		set answer [::http::data $token]
		set ncode [::http::ncode $token]
		set code [::http::code $token]
		::http::cleanup $token
	} on error err {
		set last_request_result "Could not $method $url: $err"
		msg -ERROR [namespace current] request: $last_request_result
		dui say [translate "Request to pyDE1 failed"]
		catch { ::http::cleanup $token }
		
		#message_page "Could not $method $url: $err" [translate Ok]
	}
	
	if { $status eq "ok" && $ncode == 200 } {
		try {
			set response [::json::json2dict $answer]
		} on error err {
			set last_request_result "Can't parse JSON answer: $my_err\n$answer"
			msg -WARNING [namespace current] request: $last_request_result
			dui say [translate "Request to pyDE1 failed"]
			
			#message_page "Can't parse JSON answer: $err" [translate Ok]
		}
	}
		
	#msg -INFO [namespace current] request: "$url $method => ncode=$ncode, status=$status\n$response"
	if { $last_request_result eq {} } {
		set last_request_success 1
		set last_request_result [translate {Request successful}]
	}
	
	return $response
}

# Transform the current profile (on memory, on the global settings) to JSON format and submit it to pyDE1 for storage
proc ::plugins::pyde1::profile_store_current {} {
	variable last_request_success
	variable last_request_result
	
	::profile::sync_from_legacy
	set putrest [request de1/profile/store PUT [huddle jsondump $::profile::current]]
	
	if { $last_request_success } {
		set last_request_result [translate "Profile '$::settings(profile_title)' successfully submitted"]
	}
	
	return $putrest
}

# Reads the list of the last $items shots from Visualizer and imports those shots that were not done with the DE1 as 
# local shots into the history (.shot files), and into the shots database if the SDB plugin is enabled.
# Returns a list with the clocks of the imported shots.
proc ::plugins::pyde1::visualizer_sync_history { {items {}} {propagate {}} } {
	variable settings
	set synched {}
	
	if { ![plugins enabled visualizer_upload] || ![plugins enabled SDB]} {
		msg -WARNING [namespace current] sync_history: "needs visualizer_upload and SDB plugins enabled"
		return
	} 		
	if { ![::plugins::visualizer_upload::has_credentials] } {
		msg -WARNING [namespace current] sync_history: "visualizer username or password is not defined"
		return
	}

	if { $items eq {} || ![string is integer items] } {
		set items $settings(n_sync_shots) 
	}
	
	if { $propagate eq {} } {
		# If propagation is not specified, use whatever is configured in DYE
		if { [plugins enabled DYE] } {
			set propagate $::plugins::DYE::settings(propagate_previous_shot_desc)
			if { [info exists ::plugins::DYE::settings(reset_next_plan)] } {
				set propagate [expr {$propagate && !$::plugins::DYE::settings(reset_next_plan)}]
			}
		} else {
			set propagate 0
		}
	}
	
	# Download shot list
	set shot_list [::plugins::visualizer_upload::download_shot_list 1 $items]
	if { $shot_list eq {} } {
		msg -WARNING [namespace current] visualizer_sync_history: "no shots returned from visualizer"
		return
	} else {
		set shot_list [dict get $shot_list data]
		if { [llength $shot_list] == 0 } {
			msg -WARNING [namespace current] visualizer_sync_history: "no shots returned from visualizer"
			return
		}
	}
	
	foreach shot_item $shot_list {
		set shot_clock [lindex $shot_item 1]
		set shot_id [lindex $shot_item 3]
		
		set existing_clock [::plugins::SDB::shots clock 0 "clock=$shot_clock" 1]
		if { $existing_clock ne {} } {
			msg -INFO [namespace current] visualizer_sync_history: "shot '$shot_clock' is already in the history"
			continue
		} 
	
		# Download shot and profile
		set shot [::plugins::visualizer_upload::download $shot_id all]
		set filename "[homedir]/history/[clock format $shot_clock -format $::plugins::SDB::filename_clock_format].shot"
		if { [file exists $filename] } {
			msg -WARNING [namespace current] visualizer_sync_history: "shot '$shot_clock' filename '$filename' already exists"
			continue
		}
		
		set profile {}
		if { [dict exists $shot profile_url] } {
			set profile [::plugins::visualizer_upload::download_profile [dict get $shot profile_url]]
		}

		# Propagate descriptive data from the previous shot
		if { [string is true $propagate] } {
			set desc_cols [metadata fields -domain shot -category description -propagate 1]
			array set prev_shot [::plugins::SDB::previous_shot $shot_clock $desc_cols]
			if { [array size prev_shot] > 0 } {
				foreach key $desc_cols {
					if { [dict exists $shot $key] } {
						if { $prev_shot($key) ne {} && [dict get $shot $key] eq {} } {
							#msg -INFO [namespace current] visualizer_sync_history: "propagating $key = $prev_shot($key)"
							dict set shot $key $prev_shot($key)
						}
					} else {
						#msg -INFO [namespace current] visualizer_sync_history: "propagating $key = $prev_shot($key)"
						dict set shot $key $prev_shot($key)
					}
				}
			}
		}
		
		dict append shot espresso_notes "\nPulled with pyDE1."
		
		# Create the .shot file
		set espresso_data ""
		append espresso_data "clock $shot_clock\n"
		append espresso_data "local_time {[dict get $shot start_time]}\n"
		append espresso_data "espresso_elapsed \{[dict get $shot timeframe]\}\n"
		
		set series [dict get $shot data]
		foreach {key ts} $series {
			append espresso_data "$key \{$ts\}\n"
		}
		append espresso_data "settings \{\n\tskin pyDE1\n"
		
		foreach key [dict keys $shot] {
			if { $key ni {id user_id start_time timeframe data duration image_preview profile_url} } {
				set v [dict get $shot $key]
				if { $v eq "null" } {
					set v {}
				}
				append espresso_data [subst {\t[list $key] [list $v]\n}]
			}
		}
		
		if { $profile ne {} } {
			foreach key [dict keys $profile] {
				if { $key ni {profile_title} } {
					set v [dict get $profile $key]
					if { $v eq "null" } {
						set v {}
					}
					append espresso_data [subst {\t[list $key] [list $v]\n}]
				}
			}
		}
		
		append espresso_data "\}\nmachine \{\n\}"

		write_file $filename $espresso_data	
		msg -NOTICE [namespace current] visualizer_sync_history: "Saved visualizer shot '$shot_clock' to history: $filename"
		
		# Persist the shot to the database
		array set read_shot [::plugins::SDB::load_shot $filename]
		::plugins::SDB::persist_shot read_shot
		lappend synched $shot_clock
		msg -NOTICE [namespace current] visualizer_sync_history: "Visualizer shot '$shot_clock' persisted to SDB database"
	}
	
	return $synched
}

#### "CONFIGURATION SETTINGS" PAGE ######################################################################################

namespace eval ::plugins::pyde1::pyde1_settings {
	variable widgets
	array set widgets {}
	
	variable data
	array set data {
		profile_title {}
		profile_upload_result {}
		test_pyde1_result {}
		sync_history_result {}
	}
}

# Setup the "DYE_configuration" page User Interface.
proc ::plugins::pyde1::pyde1_settings::setup {} {
	variable widgets
	set page [namespace tail [namespace current]]

	# HEADER AND BACKGROUND
	dui add dtext $page 1280 100 -tags page_title -text [translate "pyDE1 Plugin"] -style page_title

	dui add canvas_item rect $page 10 190 2550 1430 -fill "#ededfa" -width 0
	dui add canvas_item line $page 14 188 2552 189 -fill "#c7c9d5" -width 2
	dui add canvas_item line $page 2551 188 2552 1426 -fill "#c7c9d5" -width 2
	
#	dui add canvas_item rect $page 22 210 1270 1410 -fill white -width 0
#	dui add canvas_item rect $page 1290 210 2536 850 -fill white -width 0	
#	dui add canvas_item rect $page 1290 870 2536 1410 -fill white -width 0
	dui add canvas_item rect $page 22 210 1270 750 -fill white -width 0
	dui add canvas_item rect $page 22 770 1270 1410 -fill white -width 0
	dui add canvas_item rect $page 1290 210 2536 850 -fill white -width 0	
	dui add canvas_item rect $page 1290 870 2536 1410 -fill white -width 0
			
	# LEFT SIDE 1, CONNECTIONS
	set x 75; set y 250; set vspace 150; set lwidth 1050
	set panel_width 1248
	
	dui add dtext $page $x $y -text [translate "Connection"] -style section_header

	dui add entry $page [expr {$x+225}] [incr y 100] -width 34 -canvas_anchor nw -tags hostname \
		-textvariable ::plugins::pyde1::settings(hostname) \
		-label [translate "Hostname"] -label_pos [list $x $y] -label_width 300
	bind $widgets(hostname) <Return> [list ::plugins::save_settings pyde1]	

	dui add entry $page [expr {$x+225}] [incr y 100] -width 6 -canvas_anchor nw -tags port \
		-textvariable ::plugins::pyde1::settings(port) \
		-label [translate "Port"] -label_pos [list $x $y] -label_width 300
	bind $widgets(port) <Return> [list ::plugins::save_settings pyde1]	
	
	dui add dtext $page [expr {$x+600}] $y -tags {use_https_lbl use_https*} \
		-width 300 -text [translate "Use https?"]
	dui add dtoggle $page [expr {$x+$panel_width-260}] $y -anchor ne -tags use_https \
		-variable ::plugins::pyde1::settings(use_https) -command [list ::plugins::save_settings pyde1] 

	dui add dbutton $page $x [incr y 100] -anchor nw -tags test_pyde1 -style dsx_settings -bwidth 600 -bheight 150 \
		-command test_pyde1 -label [translate "Test connection"] -label_width 425 -symbol house-signal
	
	dui add variable $page [expr {$x+625}] $y -tags test_pyde1_result -width [expr {$panel_width-725}] -font_size -2
	
	# LEFT SIDE 2, PROFILES
	dui add dtext $page $x [incr y 250] -text [translate "Profiles"] -style section_header
	
	dui add variable $page $x [incr y 100] -tags profile_title -width [expr {$panel_width-150}]
	
	dui add dbutton $page $x [incr y 80] -anchor nw -tags upload_profile -style dsx_settings -bwidth 600 -bheight 150 \
		-command upload_profile -label [translate "Submit current profile"] -label_width 425 -symbol file-export

	dui add variable $page [expr {$x+625}] $y -tags profile_upload_result -width [expr {$panel_width-725}] -font_size -2
	
	dui add dbutton $page $x [incr y 225] -anchor nw -tags upload_visible_profiles -style dsx_settings -bwidth 600 -bheight 150 \
		-command upload_visible_profiles -label [translate "Submit visible profiles"] -label_width 425 -symbol file-export

	# RIGHT SIDE 1, SHOTS	
	set x 1350; set y 250
	dui add dtext $page $x $y -text [translate "Shot history"] -style section_header
	
	dui add entry $page [expr {$x+600}] [incr y 100] -width 4 -canvas_anchor nw -tags n_sync_shots \
		-textvariable ::plugins::pyde1::settings(n_sync_shots) \
		-label [translate "Number of shots to check"] -label_pos [list $x $y] -label_width 580
	bind $widgets(n_sync_shots) <Return> [list ::plugins::save_settings pyde1]	

	dui add dbutton $page $x [incr y 150] -anchor nw -tags visualizer_sync_history -style dsx_settings -bwidth 600 -bheight 150 \
		-command visualizer_sync_history -label [translate "Import shots using Visualizer"] -label_width 425 -symbol file-import

	dui add variable $page [expr {$x+625}] $y -tags sync_history_result -width [expr {$panel_width-725}] -font_size -2
	
	
	# FOOTER
	dui add dbutton $page 1035 1460 -tags page_done -style insight_ok -command page_done -label [translate Ok]
	
}

proc ::plugins::pyde1::pyde1_settings::load { page_to_hide page_to_show args } {
	return 1
}

proc ::plugins::pyde1::pyde1_settings::show { page_to_hide page_to_show } {
	variable data
	set page [namespace tail [namespace current]]
	
	set data(profile_title) "[translate {Current profile}]: $::settings(profile_title)"
	if { [string is true $::settings(profile_has_changed)] } {
		append data(profile_title) "* (modified)"
	}
	
	#dui item config $page profile_upload_result -fill [dui aspect get dtext fill -theme [dui page theme $page]]
}
	
proc ::plugins::pyde1::pyde1_settings::test_pyde1 {} {
	variable data
	set page [namespace tail [namespace current]]
	
	set data(test_pyde1_result) [translate "Testing..."]
	dui item config $page profile_upload_result -fill [dui aspect get dtext fill -theme [dui page theme $page]]

	set ver [::plugins::pyde1::request version]
	if { $::plugins::pyde1::last_request_success } {
		if { [dict size $ver] > 0 } {
			set data(test_pyde1_result) "Connected to pyDE1 v[dict get $ver module_versions pyDE1] running on [dict get $ver platform]"
		} else {
			dui item config $page test_pyde1_result -fill [dui aspect get dtext fill -theme [dui page theme $page] -style error]
			set data(test_pyde1_result) [translate {ERROR: Empty version response}]
		}
	} else {
		dui item config $page test_pyde1_result -fill [dui aspect get dtext fill -theme [dui page theme $page] -style error]
		set data(test_pyde1_result) $::plugins::pyde1::last_request_result
	}
}

proc ::plugins::pyde1::pyde1_settings::upload_profile {} {
	variable data
	set page [namespace tail [namespace current]]
	
	set data(profile_upload_result) [translate "Submitting profile..."]
	dui item config $page profile_upload_result -fill [dui aspect get dtext fill -theme [dui page theme $page]]
	
	set upload_result [::plugins::pyde1::profile_store_current]

	set data(profile_upload_result) $::plugins::pyde1::last_request_result
	if { !$::plugins::pyde1::last_request_success } {
		dui item config $page profile_upload_result -fill [dui aspect get dtext fill -theme [dui page theme $page] -style error]
	}
}

proc ::plugins::pyde1::pyde1_settings::visualizer_sync_history {} {
	variable data
	set page [namespace tail [namespace current]]
	
	set data(sync_history_result) [translate "Checking Visualizer shots not in local history..."]
	dui item config $page sync_history_result -fill [dui aspect get dtext fill -theme [dui page theme $page]]
	
	set synched [::plugins::pyde1::visualizer_sync_history $::plugins::pyde1::settings(n_sync_shots)]
	
	if { $::plugins::pyde1::last_request_success } {
		if { [llength $synched] == 0 } {
			set data(sync_history_result) [translate {No shots needed importing}]
		} else {
			set data(sync_history_result) "[llength $synched] shots have been imported."
		}
	} else {
		set data(sync_history_result) $::plugins::pyde1::last_request_result
		dui item config $page sync_history_result -fill [dui aspect get dtext fill -theme [dui page theme $page] -style error]
	}
}

proc ::plugins::pyde1::pyde1_settings::page_done {} {
	dui say [translate {Done}] button_in
	dui page close_dialog
}

