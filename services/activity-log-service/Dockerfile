FROM node:22-alpine

WORKDIR /app

COPY services/activity-log-service/package*.json ./
RUN npm ci

COPY services/activity-log-service/tsconfig.json ./
COPY services/activity-log-service/src ./src

RUN npm run build

EXPOSE 3005

CMD ["npm", "run", "start"]
