# This file is used to run necessary startup and various tasks in the stack

FROM debian:9

RUN apt-get update && apt-get install -y curl

RUN mkdir /app
COPY startup.sh /app
WORKDIR /app
RUN chmod +x startup.sh

CMD ./startup.sh