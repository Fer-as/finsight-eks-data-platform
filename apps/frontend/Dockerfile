FROM node:24-alpine AS development
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
