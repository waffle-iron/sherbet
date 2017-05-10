defmodule Sherbet.Service.Contact.Communication.Method.Mobile do
    @moduledoc """
      Support mobile contacts.
    """

    @behaviour Sherbet.Service.Contact.Communication.Method

    alias Sherbet.Service.Contact.Communication.Method.Mobile
    require Logger
    import Ecto.Query

    #todo: should error reasons expose changeset.errors?

    def add(identity, mobile) do
        contact =
            %Mobile.Model{}
            |> Mobile.Model.insert_changeset(%{ identity: identity, mobile: mobile })
            |> Sherbet.Service.Repo.insert

        case contact do
            { :ok, _ } -> :ok
            { :error, changeset } ->
                Logger.debug("add: #{inspect(changeset.errors)}")
                { :error, "Failed to add mobile contact" }
        end
    end

    def remove(identity, mobile) do
        query = from contact in Mobile.Model,
            where: contact.identity == ^identity and contact.mobile == ^mobile

        case Sherbet.Service.Repo.delete_all(query) do
            { 0, _ } ->
                Logger.debug("remove: #{identity}, #{mobile}")
                { :error, "Failed to remove the contact" }
            _ -> :ok
        end
    end

    def verified?(identity, mobile) do
        query = from contact in Mobile.Model,
            where: contact.identity == ^identity and contact.mobile == ^mobile,
            select: contact.verified

        case Sherbet.Service.Repo.one(query) do
            nil -> { :error, "Mobile does not exist" }
            verified -> { :ok, verified }
        end
    end

    def contacts(identity) do
        query = from contact in Mobile.Model,
            where: contact.identity == ^identity,
            select: { contact.verified, contact.mobile }

        {
            :ok,
            Sherbet.Service.Repo.all(query)
            |> Enum.map(fn
                { true, mobile } -> { :verified, mobile }
                { false, mobile } -> { :unverified, mobile }
            end)
        }
    end

    def request_removal(mobile) do
        query = from contact in Mobile.Model,
            where: contact.mobile == ^mobile,
            select: { contact.id, contact.verified }

        with { :mobile, { id, false } } <- { :mobile, Sherbet.Service.Repo.one(query) },
             { :key, { :ok, _ } } <- { :key, Sherbet.Service.Repo.insert(Mobile.RemovalKey.Model.changeset(%Mobile.RemovalKey.Model{}, %{ mobile_id: id, key: generate_key() })) } do
                #todo: send unique key to the mobile (use SMS service to send the message)
                :ok
        else
            { :mobile, nil } -> { :error, "Mobile does not exist" }
            { :mobile, { _, true } } -> { :error, "Mobile is verified" }
            { :key, { :error, changeset } } ->
                Logger.debug("request_verification: #{inspect(changeset.errors)}")
                { :error, "Failed to create removal key for mobile" }
        end
    end

    def finalise_removal(mobile, key) do
        query = from removal in Mobile.RemovalKey.Model,
            where: removal.key == ^key,
            join: contact in Mobile.Model, on: contact.id == removal.mobile_id and contact.mobile == ^mobile,
            select: contact

        case Sherbet.Service.Repo.one(query) do
            nil -> { :error, "Invalid removal attempt" }
            %Mobile.Model{ verified: true } -> { :error, "Mobile is verified" }
            contact = %Mobile.Model{ verified: false } ->
                case Sherbet.Service.Repo.delete(contact) do
                    { :ok, _ } -> :ok
                    { :error, changeset } ->
                        Logger.debug("finalise_removal: #{inspect(changeset.errors)}")
                        { :error, "Failed to remove mobile" }
                end
        end
    end

    def request_verification(identity, mobile) do
        query = from contact in Mobile.Model,
            where: contact.mobile == ^mobile and contact.identity == ^identity,
            select: { contact.id, contact.verified }

        with { :mobile, { id, false } } <- { :mobile, Sherbet.Service.Repo.one(query) },
             { :key, { :ok, _ } } <- { :key, Sherbet.Service.Repo.insert(Mobile.VerificationKey.Model.changeset(%Mobile.VerificationKey.Model{}, %{ mobile_id: id, key: generate_key() })) } do
                #todo: send unique key to the mobile (use SMS service to send the message)
                :ok
        else
            { :mobile, nil } -> { :error, "Mobile does not exist" }
            { :mobile, { _, true } } -> { :error, "Mobile is verified" }
            { :key, { :error, changeset } } ->
                Logger.debug("request_verification: #{inspect(changeset.errors)}")
                { :error, "Failed to create verification key for mobile" }
        end
    end

    def finalise_verification(identity, mobile, key) do
        query = from verification in Mobile.VerificationKey.Model,
            where: verification.key == ^key,
            join: contact in Mobile.Model, on: contact.id == verification.mobile_id and contact.identity == ^identity and contact.mobile == ^mobile,
            select: contact

        case Sherbet.Service.Repo.one(query) do
            nil -> { :error, "Invalid verification attempt" }
            %Mobile.Model{ verified: true } -> { :error, "Mobile is verified" }
            contact = %Mobile.Model{ verified: false, id: id } ->
                case Sherbet.Service.Repo.update(Mobile.Model.update_changeset(contact, %{ verified: true })) do
                    { :ok, _ } ->
                        query = from verification in Mobile.VerificationKey.Model,
                            where: verification.mobile_id == ^id

                        Sherbet.Service.Repo.delete_all(query)

                        :ok
                    { :error, changeset } ->
                        Logger.debug("finalise_verification: #{inspect(changeset.errors)}")
                        { :error, "Failed to verify mobile" }
                end
        end
    end

    defp generate_key() do
        0..5
        |> Enum.map(fn _ -> :crypto.rand_uniform(48, 57) end)
        |> to_string()
    end
end