# auto_planka

The auto_planka script makes a few changes to the Planka database to better suit its use at PDX Hackerspace.

Planka doesn't currently support "public" boards or projects though this appears to be on its roadmap.

At PDX Hackerspace we're using Planka as a kanban board to share projects with our members. While we want to allow for
private projects, some will be "public" - accessible to all members.

1. We want to have "public" projects whose boards automatically have all members added to them
2. All Planka admins should automatically be managers of boards in public projects
3. Labels on any board in a public project should be available on all other boards in public projects

This script takes a simple JSON file that lists the IDs of public projects and once per minute will attempt to add all users to the boards.
This works for our use case; we have few enough users that the overhead is low for us.

To make labels work properly this SQL command should be run on the Planka database:
```
ALTER TABLE label ADD UNIQUE ( name, board_id);
```

This disallows multiple labels with the same name on a board, greatly simplifying the `auto_planka` script.

In lieu of Planka supporting this functionality directly it would no doubt be better implemented directly in the database using stored
procedures and triggers.
