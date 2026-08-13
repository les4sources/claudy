require "rails_helper"

# Issue #155 — le grand livre. Deux règles dures : une écriture ne vaut jamais
# zéro (contrainte en base), et une écriture rattachée à un décompte émis est
# immuable — y compris en console.
RSpec.describe AccountEntry, type: :model do
  let(:account) { MemberAccount.create!(kind: "entity", name: "Semisto") }

  def entry(attrs = {})
    account.account_entries.create!({ entry_date: Date.new(2024, 5, 1), amount_cents: 1_250,
                                      label: "Bières", flow: "bar" }.merge(attrs))
  end

  describe "montant" do
    it "refuse zéro en Ruby" do
      record = account.account_entries.new(entry_date: Date.current, amount_cents: 0)

      expect(record).not_to be_valid
      expect(record.errors[:amount_cents]).to be_present
    end

    it "refuse zéro EN BASE, validations contournées" do
      record = account.account_entries.new(entry_date: Date.current, amount_cents: 0)

      expect { record.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "accepte un montant négatif — une écriture en faveur du compte" do
      expect(entry(amount_cents: -3_000)).to be_persisted
    end
  end

  describe "unicité" do
    it "refuse un idempotency_key en doublon" do
      entry(idempotency_key: "bar-2024-05-01-42")

      expect { entry(idempotency_key: "bar-2024-05-01-42") }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "refuse un client_uuid en doublon" do
      entry(client_uuid: "b6e1e2f0-0000-4000-8000-000000000001")

      expect { entry(client_uuid: "b6e1e2f0-0000-4000-8000-000000000001") }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "#locked?" do
    it "est vrai dès qu'un décompte est rattaché" do
      expect(entry(account_statement_id: 42)).to be_locked
    end

    it "est vrai dès que locked_at est renseigné" do
      expect(entry(locked_at: Time.current)).to be_locked
    end

    it "est faux sur une écriture libre" do
      expect(entry).not_to be_locked
    end
  end

  describe "immuabilité d'une écriture verrouillée" do
    let!(:locked) { entry(account_statement_id: 42) }

    it "refuse un update" do
      expect { locked.update!(label: "Falsifié") }.to raise_error(AccountEntry::Locked)
      expect(locked.reload.label).to eq("Bières")
    end

    it "refuse un destroy" do
      expect { locked.destroy }.to raise_error(AccountEntry::Locked)
      expect(AccountEntry.find_by(id: locked.id)).to be_present
    end

    it "refuse une suppression douce" do
      expect { locked.soft_delete! }.to raise_error(AccountEntry::Locked)
    end

    it "laisse poser le verrou une première fois" do
      free = entry
      expect { free.update!(locked_at: Time.current) }.not_to raise_error
      expect { free.update!(label: "Trop tard") }.to raise_error(AccountEntry::Locked)
    end

    it "laisse une écriture libre se modifier et se supprimer" do
      free = entry
      expect { free.update!(label: "Corrigé") }.not_to raise_error
      expect { free.soft_delete! }.not_to raise_error
    end
  end

  describe "#reverse!" do
    it "crée l'écriture opposée sans jamais toucher à l'originale" do
      original = entry(account_statement_id: 42)

      reversal = original.reverse!(label: "Erreur de saisie")

      expect(reversal.amount_cents).to eq(-1_250)
      expect(reversal.kind).to eq("reversal")
      expect(reversal.reversal_of_id).to eq(original.id)
      expect(reversal.entry_date).to eq(Date.current)
      expect(reversal.label).to eq("Erreur de saisie")

      original.reload
      expect(original.amount_cents).to eq(1_250)
      expect(original.label).to eq("Bières")
      expect(original.updated_at).to eq(original.reload.updated_at)
    end

    it "ramène le solde à son point de départ" do
      original = entry
      original.reverse!

      expect(account.reload.balance_cents).to eq(0)
    end

    it "se passe de libellé et en fabrique un" do
      expect(entry.reverse!.label).to include("Contre-écriture")
    end
  end
end
