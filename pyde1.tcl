#######################################################################################################################
### A Decent DE1app extension for sending profiles to, and reading shots from, pyDE1.
###  
### Source code available in GitHub: https://github.com/ebengoechea/de1app_plugin_pyde1/
### This code is released under GPLv3 license. See LICENSE file under the DE1 source folder in github.
###
### By Enrique Bengoechea <enri.bengoechea@gmail.com> 
########################################################################################################################
#set ::skindebug 1
#plugins enable pyde1
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
	
	# PRELIMINARY TESTING 
	set v [request version]
	if { [dict size $v] > 0 } {
		msg -INFO [namespace current] "PLATFORM: [dict get $v platform]"
	}
	
	# Upload a JSON profile for storage. Need to take it from a file as on the spot conversion to JSON not yet supported 
	set profileTitle "Backflush cleaning"
	set profileFile "[homedir]/profiles_v2/${profileTitle}.json"
	
	# NOTE: Curl profile upload uses headers: Accept */* Content-Type application/x-www-form-urlencoded and Content-Length with the size.
	#	Doesn't seem required, though.
	msg -INFO [namespace current] main: "PROFILE length: [string length $profileFile]"
	
	set putres [request de1/profile/store [read_binary_file $profileFile]]
}

# Paint settings screen
proc ::plugins::pyde1::preload {} {
	package require de1_logging 1.0
	package require de1_dui 1.0
	
	check_settings
	plugins save_settings pyde1
	
#	setup_default_aspects
	dui page add pyde1_settings -namespace true -theme default -type fpdialog
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
}


# Defines the pyde1-specific aspect styles for the default theme. These are always needed even if the current theme used is 
# another one, to have a default and to build the settings page with the default theme.
proc ::plugins::pyde1::setup_default_aspects { args } {
	set theme default
	
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

# Using http package
proc ::plugins::pyde1::request { endpoint {method GET} {query {}} {headers {}} {body {}} } {
	variable settings
	if { $endpoint eq "" } {
		msg -WARNING [namespace current] request: "'endpoint' not specified"
		return
	}	
	if { $method ni {GET PUT PATCH} } {
		msg -WARNING [namespace current] request: "'method' has to be one of GET, PUT or PATCH"
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
		msg -ERROR [namespace current] request: "Can't register $settings(hostname):$settings(port) - $err: $err"
		dui say [translate "Request to pyDE1 failed"]
		
		#message_page "Can't register $settings(hostname):$settings(port) - $err" [translate Ok]
		return
	}
	
	set status ""
	set answer ""
	set code ""
	set ncode ""
	set response ""
	try {
		set token [::http::geturl $url -method $method -type "application/json" -query $query  -timeout 10000]
		set status [::http::status $token]
		set answer [::http::data $token]
		set ncode [::http::ncode $token]
		set code [::http::code $token]
		::http::cleanup $token
	} on error err {
		msg -ERROR [namespace current] request: "Could not $method $url: $err"
		dui say [translate "Request to pyDE1 failed"]
		catch { ::http::cleanup $token }
		
		#message_page "Could not $method $url: $err" [translate Ok]
	}
	
	if { $status eq "ok" && $ncode == 200 } {
		try {
			set response [::json::json2dict $answer]
		} on error err {
			msg -WARNING [namespace current] request: "Can't parse JSON answer: $my_err\n$answer"
			dui say [translate "Request to pyDE1 failed"]
			
			#message_page "Can't parse JSON answer: $err" [translate Ok]
		}
	}
		
	msg -INFO [namespace current] request: "$url $method => ncode=$ncode, status=$status\n$response"
	return $response
}


#### "CONFIGURATION SETTINGS" PAGE ######################################################################################

namespace eval ::plugins::pyde1::pyde1_settings {
	variable widgets
	array set widgets {}
	
	variable data
	array set data {
		page_name "::plugins::pyde1::pyde1_settings"
	}
}

# Setup the "DYE_configuration" page User Interface.
proc ::plugins::pyde1::pyde1_settings::setup {} {
	variable widgets
	set page [namespace tail [namespace current]]

	# HEADER AND BACKGROUND
	dui add dtext $page 1280 100 -tags page_title -text [translate "pyDE1 Data Plugin Settings"] -style page_title

	dui add canvas_item rect $page 10 190 2550 1430 -fill "#ededfa" -width 0
	dui add canvas_item line $page 14 188 2552 189 -fill "#c7c9d5" -width 2
	dui add canvas_item line $page 2551 188 2552 1426 -fill "#c7c9d5" -width 2
	
	dui add canvas_item rect $page 22 210 1270 1410 -fill white -width 0
	dui add canvas_item rect $page 1290 210 2536 850 -fill white -width 0	
	dui add canvas_item rect $page 1290 870 2536 1410 -fill white -width 0
		
	# LEFT SIDE
	set x 75; set y 250; set vspace 150; set lwidth 1050
	set panel_width 1248
	
#	dui add dtext $page $x $y -text [translate "General options"] -style section_header
#		
#	dui add dtext $page $x [incr y 100] -tags {propagate_previous_shot_desc_lbl propagate_previous_shot_desc*} \
#		-width [expr {$panel_width-250}] -text [translate "Propagate Beans, Equipment, Ratio & People from last to next shot"]
#	dui add dtoggle $page [expr {$x+$panel_width-100}] $y -anchor ne -tags propagate_previous_shot_desc \
#		-variable ::plugins::DYE::settings(propagate_previous_shot_desc) -command propagate_previous_shot_desc_change 
#	
#	dui add dtext $page [expr {$x+150}] [incr y $vspace] -tags {reset_next_plan_lbl reset_next_plan*} \
#		-width [expr {$panel_width-400}] -text [translate "Reset next plan after pulling a shot"] -initial_state disabled
#	dui add dtoggle $page [expr {$x+$panel_width-100}] $y -anchor ne -tags reset_next_plan \
#		-variable ::plugins::DYE::settings(reset_next_plan) -command reset_next_plan_change -initial_state disabled
#	
#	dui add dtext $page $x [incr y $vspace] -tags {describe_from_sleep_lbl describe_from_sleep*} \
#		-width [expr {$panel_width-250}] -text [translate "Icon on screensaver to describe last shot without waking up the DE1"]
#	dui add dtoggle $page [expr {$x+$panel_width-100}] $y -anchor ne -tags describe_from_sleep \
#		-variable ::plugins::DYE::settings(describe_from_sleep) -command describe_from_sleep_change 
#	
##	dui add dtext $page $x [incr y $vspace] -tags {backup_modified_shot_files_lbl backup_modified_shot_files*} \
##		-width [expr {$panel_width-250}] -text [translate "Backup past shot files when they are modified (.bak extension)"]
##	dui add dtoggle $page [expr {$x+$panel_width-100}] $y -anchor ne -tags backup_modified_shot_files \
##		-variable ::plugins::DYE::settings(backup_modified_shot_files) -command backup_modified_shot_files_change 
#
#	dui add dtext $page $x [incr y $vspace] -tags {use_stars_to_rate_enjoyment_lbl use_stars_to_rate_enjoyment*} \
#		-width [expr {$panel_width-700}] -text [translate "Rate enjoyment using"]
#	dui add dselector $page [expr {$x+$panel_width-100}] $y -bwidth 600 -anchor ne -tags use_stars_to_rate_enjoyment \
#		-variable ::plugins::DYE::settings(use_stars_to_rate_enjoyment) -values {1 0} \
#		-labels [list [translate {0-5 stars}] [translate {0-100 slider}]] -command [list ::plugins::save_settings DYE]
#
#	dui add dtext $page $x [incr y $vspace] -tags {relative_dates_lbl relative_dates*} \
#		-width [expr {$panel_width-700}] -text [translate "Format of shot dates in DYE pages"]
#	dui add dselector $page [expr {$x+$panel_width-100}] $y -bwidth 600 -anchor ne -tags relative_dates \
#		-variable ::plugins::DYE::settings(relative_dates) -values {1 0} \
#		-labels [list [translate Relative] [translate Absolute]] -command [list ::plugins::save_settings DYE]
#
#	dui add dtext $page $x [incr y $vspace] -tags {date_input_format_lbl date_input_format*} \
#		-width [expr {$panel_width-700}] -text [translate "Input dates format"]
#	dui add dselector $page [expr {$x+$panel_width-100}] $y -bwidth 600 -anchor ne -tags date_input_format \
#		-variable ::plugins::DYE::settings(date_input_format) -values {MDY DMY YMD} \
#		-labels [list [translate MDY] [translate DMY] [translate YMD]] -command [list [namespace current]::roast_date_format_change]
#
#	dui add entry $page [expr {$x+$panel_width-100}] [incr y $vspace] -width 12 -canvas_anchor ne -tags roast_date_format \
#		-textvariable ::plugins::DYE::settings(roast_date_format) -vcmd {return [expr {[string len %P]<=15}]} -justify right \
#		-label [translate "Roast date format"] -label_pos [list $x $y]
#	bind $widgets(roast_date_format) <Leave> [list + [namespace current]::roast_date_format_change]
#	
#	dui add variable $page [expr {$x+$panel_width-450}] $y -width 300 -anchor ne -justify right -tags roast_date_example \
#		-fill [dui aspect get dselector selectedfill -theme default]
#	
#	# RIGHT SIDE, TOP
#	set x 1350; set y 250
#	dui add dtext $page $x $y -text [translate "DSx skin options"] -style section_header
#	
#	dui add dtext $page $x [incr y 100] -tags {show_shot_desc_on_home_lbl show_shot_desc_on_home*} \
#		-width [expr {$panel_width-375}] -text [translate "Show next & last shot description summaries on DSx home page"]
#	dui add dtoggle $page [expr {$x+$panel_width-100}] $y -anchor ne -tags show_shot_desc_on_home \
#		-variable ::plugins::DYE::settings(show_shot_desc_on_home) -command show_shot_desc_on_home_change 
#	
#	incr y [expr {int($vspace * 1.40)}]
#	
#	dui add dtext $page $x $y -tags shot_desc_font_color_label -width 725 -text [translate "Color of shot descriptions summaries"]
#
#	dui add dbutton $page [expr {$x+$panel_width-100}] $y -anchor ne -tags shot_desc_font_color -style dsx_settings \
#		-command shot_desc_font_color_change -label [translate "Change color"] -label_width 250 \
#		-symbol paint-brush -symbol_fill $::plugins::DYE::settings(shot_desc_font_color)
#
#	dui add dbutton $page [expr {$x+700}] [expr {$y+[dui aspect get dbutton bheight -style dsx_settings]}] \
#		-bwidth 425 -bheight 100 -anchor se -tags use_default_color \
#		-shape outline -outline $::plugins::DYE::default_shot_desc_font_color -arc_offset 35 \
#		-label [translate {Use default color}] -label_fill $::plugins::DYE::default_shot_desc_font_color \
#		-label_font_size -1 -command set_default_shot_desc_font_color 
#
#	# RIGHT SIDE, BOTTOM
#	set y 925
#	dui add dtext $page $x $y -text [translate "Insight / MimojaCafe skin options"] -style section_header
#	
#	dui add dtext $page $x [incr y 100] -tags default_launch_action_label -width 725 \
#		-text [translate "Default action when DYE icon or button is tapped"]
#	
#	dui add dselector $page [expr {$x+$panel_width-100}] $y -bwidth 400 -bheight 271 -orient v -anchor ne -values {last next dialog} \
#		-variable ::plugins::DYE::settings(default_launch_action) -labels {"Describe last" "Plan next" "Launch dialog"} \
#		-command [list ::plugins::save_settings DYE]
	
	# FOOTER
	dui add dbutton $page 1035 1460 -tags page_done -style insight_ok -command page_done -label [translate Ok]
}

proc ::plugins::pyde1::pyde1_settings::load { page_to_hide page_to_show args } {
	return 1
}

proc ::plugins::pyde1::pyde1_settings::show { page_to_hide page_to_show } {
}


proc ::plugins::pyde1::pyde1_settings::page_done {} {
	dui say [translate {Done}] button_in
	dui page close_dialog
}

