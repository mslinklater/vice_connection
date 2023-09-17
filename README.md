# vice_connection
Godot addon to remote connect with the VICE emulator

Using this GDScript addon you can connect and control/interrogate the VICE emulator. It works best when you build VICE with the --enable-cpuhistory flag. If you don't know how to do that then go read the VICE documentation first...

## Installation

Just copy the contents of this repo into a folder inside the 'addons' folder of your Godot project

## Instructions

The only API your program should be using is the ViceConnection class. Connect the signals to your own delegate methods in your program... the public API is the stuff which does not begin with an underscore.

## Release Notes

### V0.1 - Initial release

* Connects to both the binary and monitor connections on VICE.
* Send and receive info via the remote monitor - same sort of functionality as telnet
* Send and receive some packets via the binary monitor connection - still work to do on this
