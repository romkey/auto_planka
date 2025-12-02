# auto_planka

The auto_planka script makes a few changes to the Planka database to better suit its use at PDX Hackerspace.

Planka doesn't currently support "public" boards or projects though this appears to be on its roadmap.

At PDX Hackerspace we're using Planka as a kanban board to share projects with our members. While we want to allow for
private projects, some will be "public" - accessible to all members.

1. We want to have "public" projects whose boards automatically have all members added to them
2. All Planka admins should automatically be managers of boards in public projects
3. Labels on any board in a public project should be available on all other boards in public projects

This script takes a simple JSON file that lists the IDs of public projects and periodically adds all users to the boards.
This works for our use case; we have few enough users that the overhead is low for us.

## Configuration

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `POSTGRESQL` | Yes | - | PostgreSQL connection string (e.g., `postgres://user:pass@host:5432/planka_db`) |
| `CONFIG_PATH` | No | `config.json` | Path to the JSON configuration file |
| `SLEEP_INTERVAL` | No | `60` | Seconds between sync runs |
| `DEFAULT_ROLE` | No | `editor` | Role assigned to users on public boards (`editor` or `viewer`) |
| `LOG_LEVEL` | No | `INFO` | Logging verbosity (`DEBUG`, `INFO`, `WARN`, `ERROR`, `FATAL`) |

### Config File

Create a `config.json` file (or specify a custom path with `CONFIG_PATH`):

```json
{
  "public_project_ids": ["123456789", "987654321"]
}
```

To find project IDs, query your Planka database:

```sql
SELECT id, name FROM project;
```

## Database Setup

To make labels work properly, this SQL command should be run on the Planka database:

```sql
ALTER TABLE label ADD UNIQUE (name, board_id);
```

This disallows multiple labels with the same name on a board, greatly simplifying the sync logic.

## Docker Image

Docker images are automatically built and pushed to GitHub Container Registry on every push to `main` and for version tags.

### Using the Pre-built Image

Pull the latest image:

```bash
docker pull ghcr.io/romkey/auto_planka:latest
```

Or use a specific version:

```bash
docker pull ghcr.io/romkey/auto_planka:v1.0.0
```

### Running with Docker Compose

1. Copy `.env.example` to `.env` and configure your PostgreSQL connection string
2. Create your `config/config.json` with public project IDs
3. Run the container:

```bash
docker compose up -d
```

View logs:

```bash
docker compose logs -f auto_planka
```

### Using the Pre-built Image with Docker Compose

To use the pre-built image instead of building locally, update `docker-compose.yml`:

```yaml
services:
  auto_planka:
    image: ghcr.io/romkey/auto_planka:latest
    # comment out or remove the 'build:' section
```

## Development

For development, uncomment the `dockerfile: Dockerfile.dev` line in `docker-compose.yml` and run:

```bash
docker compose run auto_planka /bin/sh
```

## Notes

In lieu of Planka supporting this functionality directly, it would no doubt be better implemented directly in the database using stored procedures and triggers.
