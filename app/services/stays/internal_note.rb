module Stays
  # Conversions et test de vacuité de la note INTERNE d'un séjour, devenue du
  # texte riche (issue #313). Regroupés ici parce que cinq appelants en ont
  # besoin — le formulaire, la modale, le rapatriement des notes d'origine, le
  # refus et la fusion de séjours — et qu'une règle de vacuité dupliquée finit
  # toujours par diverger d'un appelant à l'autre.
  module InternalNote
    module_function

    # Texte brut → HTML, à l'identique de ce que rendait `simple_format` avant la
    # bascule : double saut de ligne = paragraphe, simple saut = `<br />`, contenu
    # échappé. C'est cette équivalence qui garantit qu'une note migrée s'affiche
    # exactement comme avant.
    def to_html(text)
      return "" if text.to_s.strip.blank?

      ActionController::Base.helpers.simple_format(text.to_s).to_s
    end

    # Un éditeur de texte riche « vidé » ne renvoie pas une chaîne vide mais du
    # HTML creux (`<div><br></div>`, `<p><br></p>`) : sans ce test, vider une note
    # la remplirait de balises invisibles au lieu de l'effacer.
    def blank?(html)
      content = ActionText::Content.new(html.to_s)

      content.to_plain_text.strip.blank? && content.attachments.empty?
    end

    def present?(html)
      !blank?(html)
    end

    # Texte brut extrait du HTML — ce sur quoi se comparent les notes (idempotence,
    # déduplication), jamais le balisage.
    def plain_text(html)
      ActionText::Content.new(html.to_s).to_plain_text.strip
    end

    # HTML courant de la note interne d'un séjour, sans passer par le
    # `ActionText::RichText` construit à la volée quand il n'y en a pas.
    def html_for(stay)
      stay.internal_notes.body&.to_html.to_s
    end
  end
end
