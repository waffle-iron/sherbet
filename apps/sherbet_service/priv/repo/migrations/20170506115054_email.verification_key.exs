defmodule Sherbet.Service.Repo.Migrations.Email.VerificationKey do
    use Ecto.Migration

    def change do
        create table(:email_verification_keys) do
            add :email_id, references(:emails, on_delete: :delete_all),
                null: false

            add :key, :string,
                null: false

            timestamps()
        end

        create index(:email_verification_keys, [:key], unique: false)
    end
end
