# Multi-stage build CourseFlow.Api (Глава 20.2).
# Слои упорядочены от редко меняющихся к часто меняющимся: restore кэшируется,
# пока не изменились .csproj/.props.

FROM mcr.microsoft.com/dotnet/sdk:11.0 AS build
WORKDIR /src

COPY Directory.Build.props global.json ./
COPY src/CourseFlow.Api/CourseFlow.Api.csproj src/CourseFlow.Api/
COPY src/CourseFlow.Contracts/CourseFlow.Contracts.csproj src/CourseFlow.Contracts/
COPY src/CourseFlow.ServiceDefaults/CourseFlow.ServiceDefaults.csproj src/CourseFlow.ServiceDefaults/
RUN dotnet restore src/CourseFlow.Api/CourseFlow.Api.csproj

COPY src/CourseFlow.Api/ src/CourseFlow.Api/
COPY src/CourseFlow.Contracts/ src/CourseFlow.Contracts/
COPY src/CourseFlow.ServiceDefaults/ src/CourseFlow.ServiceDefaults/
RUN dotnet publish src/CourseFlow.Api/CourseFlow.Api.csproj -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:11.0 AS runtime
WORKDIR /app

# curl нужен только для HEALTHCHECK в docker-compose
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

COPY --from=build /app .

ENV ASPNETCORE_URLS=http://+:8080 \
    DOTNET_gcServer=1
EXPOSE 8080

# Не root: образы Microsoft создают пользователя app с UID из $APP_UID (Глава 20.2)
USER $APP_UID

ENTRYPOINT ["dotnet", "CourseFlow.Api.dll"]
