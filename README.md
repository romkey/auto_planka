# auto_planka

Automatically add new users to "public" boards.

[Planka](https://github.com/plankanban/planka) doesn't currently (v1.72.2) support "public" boards. At PDX Hackerspace we want to have some boards which automatically have all users added to them.

This script takes a simple JSON file that lists the IDs of public boards and once per minute will attempt to add all users to the boards. This works for our use case; we have few enough users that the overhead is low for us.

