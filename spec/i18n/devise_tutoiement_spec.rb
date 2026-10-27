require "rails_helper"

# Claudy tutoie ses utilisateurs (Michael, 2026-10-27) : les messages de Devise
# (flash, erreurs, emails) aussi.
RSpec.describe "Messages de Devise en français" do
  it "tutoient" do
    vouvoiements = I18n.t("devise", locale: :fr).to_s.scan(/\b(?:vous|votre|vos|veuillez)\b/i)

    expect(vouvoiements).to be_empty
  end
end
