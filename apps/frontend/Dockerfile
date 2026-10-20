# Frontend images. Targets:
#   production  - built static assets served by unprivileged NGINX on 8080 (ECR repository "frontend")
#   development - Vite dev server for local Compose only
#   test        - format check, tests and build
# Base images are pinned by digest so builds are reproducible; update them deliberately.
FROM node:24-alpine@sha256:44fce696f38ba8c987c4db89954051000bbd05ffd8d8659ba15ed4a8602e937f AS development
WORKDIR /app
RUN chown node:node /app
USER node
COPY --chown=node:node apps/frontend/package*.json ./
RUN npm ci --no-audit --no-fund
COPY --chown=node:node apps/frontend/ ./
EXPOSE 5173
CMD ["npm", "run", "dev", "--", "--port", "5173", "--strictPort"]

FROM development AS test
CMD ["sh", "-c", "npm run format:check && npm test && npm run build"]

FROM development AS build
RUN npm run build

# No Node.js or development server in the production image: static files only. The page calls
# /api on the same host; the Ingress routes /api to the API, so NGINX here serves files only.
FROM nginxinc/nginx-unprivileged:1.25.3-alpine@sha256:c3f4d1ccb78e2c55e0d85883733ed1ad67a33af1cc8504f821e6140ad6037bd7 AS production
COPY apps/frontend/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
USER 101
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD ["wget", "-q", "-O", "/dev/null", "http://127.0.0.1:8080/"]
