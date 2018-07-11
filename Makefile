start: restore backup

restore: db
	docker-compose up -d restore

backup: db
	docker-compose up -d backup

db:
	docker-compose up -d db adminer

clean:
	docker-compose kill
	docker system prune -f
