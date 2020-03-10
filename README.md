# postgresql-backup-restore
Service to backup and/or restore a PostgreSQL database using S3

## How to use it
1. Create an S3 bucket to hold your backups
2. Turn versioning on for that bucket
3. Supply all appropriate environment variables
4. Run a backup and check your bucket for that backup

### Environment variables
`MODE=[backup|restore]`

`DB_HOST=` hostname of the database server

`DB_NAME=` name of the database

`DB_OPTIONS=opt1 opt2 opt3 ...` optional arguments to supply to the backup or restore commands

`DB_ROOTPASSWORD=` password for the `DB_ROOTUSER`

`DB_ROOTUSER=` database administrative user, typically "postgres" for PostgreSQL databases

`DB_USERPASSWORD=` password for the `DB_USER`

`DB_USER=` user that accesses the database (PostgreSQL "role")

`AWS_ACCESS_KEY=` used for S3 interactions

`AWS_SECRET_KEY=` used for S3 interactions

`S3_BUCKET=` _e.g., s3://database-backups_ **NOTE: no trailing slash**

>**It's recommended that your S3 bucket have versioning turned on.**

## Docker Hub
This image is built automatically on Docker Hub as [silintl/postgresql-backup-restore](https://hub.docker.com/r/silintl/postgresql-backup-restore/)

## Playing with it locally
You'll need [Docker](https://www.docker.com/get-docker), [Docker Compose](https://docs.docker.com/compose/install/), and [Make](https://www.gnu.org/software/make/).

1. `cp local.env.dist local.env` and supply variables
2. Ensure you have a `gz` dump in your S3 bucket to be used for testing.  A test database is provided as part of this project in the `test` folder. You can copy it to S3 as follows:
* `aws s3 cp test/world.sql.gz  ${S3_BUCKET}/world.sql.gz`
3. `make`

A UI into the local database will then be running at [http://localhost:8080](http://localhost:8080)
