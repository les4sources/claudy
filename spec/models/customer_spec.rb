require "rails_helper"

# == Schema Information
#
# Table name: customers
#
#  id                 :bigint           not null, primary key
#  address_city       :string
#  address_country    :string
#  address_line       :string
#  address_zip        :string
#  customer_type      :string           default("individual"), not null
#  deleted_at         :datetime
#  email              :citext
#  first_name         :string
#  language           :string           default("fr"), not null
#  last_name          :string
#  marketing_consent  :boolean          default(FALSE), not null
#  nps_eligible       :boolean          default(FALSE), not null
#  organization_name  :string
#  phone              :string
#  vat_number         :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  human_id           :bigint
#  peppol_id          :string
#  stripe_customer_id :string
#
# Indexes
#
#  index_customers_on_customer_type      (customer_type)
#  index_customers_on_email_unique_live  (email) UNIQUE WHERE (deleted_at IS NULL)
#  index_customers_on_human_id           (human_id)
#
# Foreign Keys
#
#  fk_rails_...  (human_id => humans.id)
#
RSpec.describe Customer, type: :model do
  def build_customer(**attrs)
    Customer.new({ email: "alice@example.com", customer_type: "individual" }.merge(attrs))
  end

  describe "email normalization (AC-2/AC-3)" do
    it "trims and downcases the email before validation" do
      customer = build_customer(email: "  Alice@Example.COM  ")
      customer.valid?
      expect(customer.email).to eq("alice@example.com")
    end

    it "treats a blank email as nil" do
      customer = build_customer(email: "   ")
      customer.valid?
      expect(customer.email).to be_nil
      expect(customer).not_to be_valid
    end
  end

  describe "email uniqueness among live rows (AC-3)" do
    it "rejects a second live customer with the same email (case-insensitive)" do
      build_customer(email: "dup@example.com").save!
      dup = build_customer(email: "DUP@example.com")
      expect(dup).not_to be_valid
      expect(dup.errors[:email]).to be_present
    end

    it "allows reusing the email of a soft-deleted customer" do
      first = build_customer(email: "reuse@example.com")
      first.save!
      first.soft_delete!(validate: false)

      reused = build_customer(email: "reuse@example.com")
      expect(reused).to be_valid
    end
  end

  describe "validations" do
    it "requires a known customer_type" do
      expect(build_customer(customer_type: "alien")).not_to be_valid
    end

    it "requires a known language and defaults to fr" do
      expect(build_customer.tap(&:valid?).language).to eq("fr")
      expect(build_customer(language: "es")).not_to be_valid
    end

    it "requires organization_name when the customer is an organization" do
      org = build_customer(customer_type: "organization", organization_name: nil)
      expect(org).not_to be_valid
      org.organization_name = "Les 4 Sources"
      expect(org).to be_valid
    end
  end

  # Issue #232 : un client peut exister sans email ni téléphone. Ce qui reste
  # obligatoire, c'est d'être identifiable — un nom, ou une adresse.
  describe "client sans email (issue #232)" do
    it "se sauve avec un email nil dès qu'il porte un nom" do
      customer = build_customer(email: nil, first_name: "Jean")

      expect(customer).to be_valid
      expect { customer.save! }.not_to raise_error
      expect(customer.reload.email).to be_nil
    end

    it "laisse coexister deux clients sans email" do
      build_customer(email: nil, first_name: "Jean", last_name: "Dupont").save!
      second = build_customer(email: nil, first_name: "Marie", last_name: "Durand")

      expect { second.save! }.not_to raise_error
      expect(Customer.where(email: nil).count).to eq(2)
    end

    it "accepte un email vide sur une organisation nommée" do
      org = build_customer(email: nil, customer_type: "organization", organization_name: "ACME")

      expect(org).to be_valid
    end

    it "refuse un client sans email ET sans le moindre nom" do
      orphelin = build_customer(email: nil, first_name: nil, last_name: nil, organization_name: nil)

      expect(orphelin).not_to be_valid
      expect(orphelin.errors[:base]).to include("Indiquez au moins un nom ou une adresse email")
    end

    it "refuse toujours un email présent mais mal formé" do
      expect(build_customer(email: "pas-un-email", first_name: "Jean")).not_to be_valid
    end

    it "applique toujours l'unicité quand l'email est présent" do
      build_customer(email: "unique@example.com").save!

      expect(build_customer(email: "unique@example.com", first_name: "Jean")).not_to be_valid
    end

    it "ne laisse jamais le téléphone devenir obligatoire" do
      expect(build_customer(email: nil, first_name: "Jean", phone: nil)).to be_valid
    end
  end

  describe ".exploitable_email? (AC-49)" do
    it "is false for blank or format-invalid addresses" do
      expect(Customer.exploitable_email?(nil)).to be(false)
      expect(Customer.exploitable_email?("  ")).to be(false)
      expect(Customer.exploitable_email?("not-an-email")).to be(false)
    end

    it "is true for a real address, including an OTA relay" do
      expect(Customer.exploitable_email?("bob@example.com")).to be(true)
      expect(Customer.exploitable_email?("guest-123@guest.airbnb.com")).to be(true)
    end
  end

  describe "#catch_all? (AC-47)" do
    it "is true only for the conventional catch-all email" do
      catch_all = build_customer(email: Customer::CATCH_ALL_EMAIL)
      expect(catch_all.catch_all?).to be(true)
      expect(build_customer(email: "someone@example.com").catch_all?).to be(false)
    end
  end

  describe "#name" do
    it "uses the organization name for organizations" do
      org = build_customer(customer_type: "organization", organization_name: "ACME")
      expect(org.name).to eq("ACME")
    end

    it "joins first and last name for individuals" do
      expect(build_customer(first_name: "Alice", last_name: "Martin").name).to eq("Alice Martin")
    end

    it "falls back to the email when no name is present" do
      expect(build_customer(email: "fallback@example.com").name).to eq("fallback@example.com")
    end

    # Issue #232 : le nom sert d'étiquette dans la liste des clients, le
    # `<select>` du formulaire séjour et la modale du séjour. Il ne doit JAMAIS
    # être vide, sinon la fiche devient impossible à désigner.
    it "retombe sur « Client #<id> » sans nom ni email" do
      orphelin = build_customer(email: nil, first_name: "Jean")
      orphelin.save!
      orphelin.update_columns(first_name: nil, last_name: nil)

      expect(orphelin.reload.name).to eq("Client ##{orphelin.id}")
      expect(orphelin.display_name).to eq("Client ##{orphelin.id}")
      expect(orphelin.decorate.display_name).to eq("Client ##{orphelin.id}")
    end

    it "n'est jamais vide, même sur une fiche pas encore persistée" do
      expect(build_customer(email: nil, first_name: nil).name).to be_present
    end
  end

  describe ".search" do
    it "matches on email, name and organization, case-insensitively" do
      a = build_customer(email: "search-alice@example.com", first_name: "Alice").tap(&:save!)
      b = build_customer(email: "other@example.com", customer_type: "organization",
                         organization_name: "Searchable Org").tap(&:save!)

      expect(Customer.search("ALICE")).to include(a)
      expect(Customer.search("searchable")).to include(b)
      expect(Customer.search("alice")).not_to include(b)
    end

    # Au téléphone, on tape le numéro comme on l'entend, sans les espaces.
    it "matches on the phone number, digits only, whatever the formatting" do
      a = build_customer(email: "phone@example.com", first_name: "Alice",
                         phone: "0455 13 61 42").tap(&:save!)

      expect(Customer.search("0455136142")).to include(a)
      expect(Customer.search("136142")).to include(a)
      expect(Customer.search("0999999999")).not_to include(a)
    end

    it "matches on the full name typed in one go" do
      a = build_customer(email: "full@example.com", first_name: "Jean",
                         last_name: "Dupont").tap(&:save!)

      expect(Customer.search("Jean Dupont")).to include(a)
    end

    # `%` est un joker SQL : une organisation « 100% Bio » se cherche à la lettre.
    it "escapes SQL wildcards typed by the user" do
      a = build_customer(email: "bio@example.com", customer_type: "organization",
                         organization_name: "100% Bio").tap(&:save!)
      b = build_customer(email: "other-wildcard@example.com", first_name: "Zoé").tap(&:save!)

      expect(Customer.search("100% Bio")).to include(a)
      expect(Customer.search("%")).not_to include(b)
    end
  end
end
