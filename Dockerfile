# Use OpenJDK 11 base image
FROM openjdk:11-jre-slim

# Set working directory
WORKDIR /app

# Copy the jar file
COPY target/notes-app.jar app.jar

# Create directory for SQLite database and logs
RUN mkdir -p /app/data /app/logs

# Expose port 8081
EXPOSE 8081

# Set environment variables
ENV SPRING_PROFILES_ACTIVE=linux
ENV JAVA_OPTS="-Xmx512m -Xms256m"

# Run the application
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar /app/app.jar"]
