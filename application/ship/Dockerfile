# Stage 1: Build and test the Vite application
FROM node:22-alpine AS builder

WORKDIR /app

# Copy dependency manifests first to improve layer caching
COPY package.json package-lock.json ./

# Install exact dependency versions from package-lock.json
RUN npm ci

# Copy application source
COPY . .

# Validate ship.config.json
RUN npm test

# Produce static files in /app/dist
RUN npm run build


# Stage 2: Serve only the compiled static files
FROM nginx:stable-alpine AS runtime

COPY --from=builder /app/dist/ /usr/share/nginx/html/

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
