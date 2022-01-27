# pyDE1 DE1app plugin

A plugin for the [Decent Espresso machine](https://decentespresso.com/) [Tcl DE1 app](https://github.com/decentespresso/de1app) to exchange data with [pyDE1](https://github.com/jeffsf/pyDE1).

pyDE1 offers a powerful, modern, back-end server to interface with the DE1, but at the moment only a basic demo UI is available. Features such as profile editing or shot description are missing. Until a full-featured UI is available, allowing the Tcl app to communicate with pyDE1 for some of these tasks will allow using and testing pyDE1 without giving up the advanced features.

By [Enrique Bengoechea](https://github.com/ebengoechea/).

## Planned features

1. Submit profiles to pyDE1 profile database. So these can be edited in the DE1 app and immediately send the new or modified profile to pyDE1.

2. Read pulled shots from pyDE1 shot database and store them on local .shot files on the history folder and on the [Shot DataBase](https://github.com/ebengoechea/de1app_plugin_SDB) as if they had been done from the DE1 app. So they can be browsed, analyzed, and described with [DYE](https://github.com/ebengoechea/de1app_plugin_DYE), MimojaCafe or DSx tools.
