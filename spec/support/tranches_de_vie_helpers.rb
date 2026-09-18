# Réponses mockées conformes au contrat de l'API Tranches de Vie
# (les4sources/tranchesdevie2#290), recopié dans l'issue #339 pour que le
# développement n'attende pas son déploiement.
module TranchesDeVieHelpers
  BASE_URL = "https://tranchesdevie.test".freeze
  API_KEY = "tdv-test-key".freeze

  def tdv_env!
    ENV["TRANCHESDEVIE_API_URL"] = BASE_URL
    ENV["TRANCHESDEVIE_API_KEY"] = API_KEY
  end

  def tdv_env_off!
    ENV["TRANCHESDEVIE_API_URL"] = BASE_URL
    ENV.delete("TRANCHESDEVIE_API_KEY")
  end

  def tdv_order(id: 1234, **overrides)
    {
      "id" => id,
      "order_number" => "TV-20261009-%04d" % id,
      "status" => "paid",
      "total_cents" => 27_000,
      "total_euros" => 270.0,
      "payment_method" => "stripe",
      "payment_received" => true,
      "paid_at" => "2026-09-20T10:12:00Z",
      "requires_invoice" => true,
      "customer_id" => 7,
      "party" => {
        "party_event_id" => 42,
        "held_on" => "2026-10-09",
        "slot" => "soir",
        "group_name" => "Scouts de Namur",
        "persons" => 18,
        "forfait" => true,
        "admin_url" => "#{BASE_URL}/admin/parties/42"
      },
      "customer" => {
        "id" => 7,
        "full_name" => "Alix Renard",
        "email" => "alix@example.com",
        "phone_e164" => "+32470111222"
      },
      "cancelled" => false,
      "refunded" => false,
      "refunded_at" => nil
    }.merge(overrides.transform_keys(&:to_s))
  end

  def stub_tdv_index(orders, next_link: nil)
    stub_request(:get, "#{BASE_URL}/api/v1/orders")
      .with(query: hash_including({ "kind" => "private_party", "paid" => "true" }))
      .to_return(status: 200,
                 headers: { "Content-Type" => "application/json" },
                 body: { data: orders, meta: { total: orders.size }, _links: { next: next_link } }.to_json)
  end

  def stub_tdv_order(order)
    stub_request(:get, "#{BASE_URL}/api/v1/orders/#{order['id']}")
      .to_return(status: 200,
                 headers: { "Content-Type" => "application/json" },
                 body: { data: order }.to_json)
  end

  def stub_tdv_order_missing(external_id)
    stub_request(:get, "#{BASE_URL}/api/v1/orders/#{external_id}")
      .to_return(status: 404, headers: { "Content-Type" => "application/json" }, body: { error: "not_found" }.to_json)
  end
end

RSpec.configure do |config|
  config.include TranchesDeVieHelpers
end
