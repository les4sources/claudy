module Reservations
  # Garde-fou serveur du champ téléphone du funnel. La vraie validation se fait
  # dans le navigateur (intl-tel-input, règles de numérotation par pays) ; ici,
  # on refuse seulement ce qui ne peut PAS être un numéro : des lettres, ou trop
  # peu / trop de chiffres. Le champ reste facultatif : vide = valide.
  module PhoneFormat
    module_function

    ALLOWED = /\A\+?[\d\s().\/-]+\z/

    def valid?(value)
      text = value.to_s.strip
      return true if text.empty?
      return false unless text.match?(ALLOWED)

      text.count("0-9").between?(8, 15)
    end
  end
end
