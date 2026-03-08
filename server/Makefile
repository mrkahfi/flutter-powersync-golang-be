.PHONY: run build dev keys clean

## build: compile the server binary
build:
	go build -o powersync-backend .

## run: build and run (requires .env)
run: build
	./powersync-backend

## dev: run in development mode without .env (no real keys needed)
dev: build
	DEV_MODE=true \
	POWERSYNC_URL=https://your-instance.powersync.journeyapps.com \
	PORT=8080 \
	./powersync-backend

## keys: generate a fresh RSA key pair and print base64-encoded values for .env
keys:
	@echo "Generating RSA-2048 key pair..."
	@openssl genrsa -out /tmp/ps_private.pem 2048 2>/dev/null
	@openssl rsa -in /tmp/ps_private.pem -pubout -out /tmp/ps_public.pem 2>/dev/null
	@echo ""
	@echo "POWERSYNC_PRIVATE_KEY_BASE64=$$(base64 -i /tmp/ps_private.pem)"
	@echo ""
	@echo "POWERSYNC_PUBLIC_KEY_BASE64=$$(base64 -i /tmp/ps_public.pem)"
	@rm -f /tmp/ps_private.pem /tmp/ps_public.pem

## clean: remove built binary
clean:
	rm -f powersync-backend
