FROM node:22-alpine

WORKDIR /app

COPY services/queue-coordinator-service/package*.json ./
RUN npm ci

COPY services/queue-coordinator-service/tsconfig.json ./
COPY services/queue-coordinator-service/src ./src

RUN npm run build

EXPOSE 3002

CMD ["npm", "run", "start"]
