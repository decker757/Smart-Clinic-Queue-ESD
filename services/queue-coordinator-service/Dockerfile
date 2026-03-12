FROM node:22-alpine

WORKDIR /app

COPY services/queue-coordinator-service/package*.json ./
RUN npm ci

COPY services/queue-coordinator-service/tsconfig.json ./
COPY services/queue-coordinator-service/src ./src

RUN npm run build && cp -r src/proto dist/proto

EXPOSE 3002
EXPOSE 50052

CMD ["npm", "run", "start"]
