FROM node:22-bookworm
WORKDIR /src
COPY companion/package.json companion/package-lock.json* /src/
RUN npm install
COPY companion /src
ENV CSC_IDENTITY_AUTO_DISCOVERY=false
RUN npm run dist:linux
