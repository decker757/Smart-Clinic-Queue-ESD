FROM node:22-alpine
WORKDIR /app
COPY wrappers/notification-service/package*.json ./
RUN npm ci
COPY wrappers/notification-service/tsconfig.json ./
COPY wrappers/notification-service/src ./src
RUN npm run build && cp -r src/proto dist/proto
EXPOSE 3004
CMD ["npm", "run", "start"]
