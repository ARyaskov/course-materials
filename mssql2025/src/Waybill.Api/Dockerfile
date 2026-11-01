# Waybill.Api — образ для docker compose --profile app (глава 16). Контекст сборки — корень project/waybill.
#   docker build -f src/Waybill.Api/Dockerfile -t waybill-api .
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY Directory.Build.props ./
COPY src/Waybill.Data/Waybill.Data.csproj src/Waybill.Data/
COPY src/Waybill.Api/Waybill.Api.csproj src/Waybill.Api/
RUN dotnet restore src/Waybill.Api/Waybill.Api.csproj
COPY src/Waybill.Data/ src/Waybill.Data/
COPY src/Waybill.Api/ src/Waybill.Api/
RUN dotnet publish src/Waybill.Api/Waybill.Api.csproj -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /app .
ENV ASPNETCORE_URLS=http://+:5080
EXPOSE 5080
USER $APP_UID
ENTRYPOINT ["dotnet", "Waybill.Api.dll"]
