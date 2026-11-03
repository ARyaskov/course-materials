defmodule KlaxonWeb.Presence do
  @moduledoc """
  Присутствие дежурных.

  Presence хранит состояние на всех узлах кластера и синхронизирует его
  без единого хранилища: каждый узел знает своих, а расхождения сходятся
  обменом дельт. Записи узла исчезают, если узел выпал из кластера.
  """

  use Phoenix.Presence,
    otp_app: :klaxon,
    pubsub_server: Klaxon.PubSub
end
