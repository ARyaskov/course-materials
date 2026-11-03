# Мок канала доставки. Подменяется поведение `Klaxon.Notifications.Channel`,
# а не конкретный модуль: тест задаёт ожидания, а не переписывает реализацию.
Mox.defmock(Klaxon.ChannelMock, for: Klaxon.Notifications.Channel)
