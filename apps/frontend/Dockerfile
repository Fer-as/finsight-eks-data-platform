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
FROM nginxinc/nginx-unprivileged:1.30.6-alpine3.24@sha256:f5116ed4606f3eb015dd4a8e28cb9b351476dc0ad4bc6e9f93b19cec130cdf03 AS production
COPY apps/frontend/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
USER 101
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD ["wget", "-q", "-O", "/dev/null", "http://127.0.0.1:8080/"]
