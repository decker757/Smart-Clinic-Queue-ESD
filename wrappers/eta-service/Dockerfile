FROM node:22-alpine
WORKDIR /app
COPY wrappers/eta-service/package*.json ./
RUN npm ci
COPY wrappers/eta-service/tsconfig.json ./
COPY wrappers/eta-service/src ./src
RUN npm run build && cp -r src/proto dist/proto
EXPOSE 50054
CMD ["npm", "run", "start"]
