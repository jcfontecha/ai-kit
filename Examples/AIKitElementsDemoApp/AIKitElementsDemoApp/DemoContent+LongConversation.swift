import Foundation
import AIKit

extension DemoContent {
  nonisolated static var longConversationMessages: [ChatMessage] {
    [
      Self.user("demo.long.user.1", """
      I’m putting together a **mini brand guide** for a fictional boutique hotel called *The Juniper Atlas*.

      I want the assistant to behave like a thoughtful creative director: lots of detail, lots of words, and a few “tool” steps where we generate images.

      Can you propose:
      1) a story/voice,
      2) a color + typography direction,
      3) a starter set of *4 poster concepts* (with copy),
      and then generate a few example images we can use as placeholders?
      """),

      Self.assistant("demo.long.assistant.1", parts: [
        Self.text("demo.long.assistant.1.text.1", """
        Great brief. I’ll treat this like a compact creative direction doc you can drop into a deck.

        **High-level concept**
        *The Juniper Atlas* is a hotel for people who collect places the way others collect records: tactile, personal, a little imperfect, and quietly aspirational. Not “luxury” by shine—luxury by intention.

        **Voice**
        - *Warmly specific*: sensory details, not hype.
        - *Modern, not minimal*: clean sentences, but not sterile.
        - *Curated curiosity*: “Here’s a thing you didn’t know you wanted.”

        **Personality keywords**
        Pine resin • linen • paper maps • soft brass • morning espresso • twilight walks
        """),
        Self.text("demo.long.assistant.1.text.2", """
        **Color direction**
        - Juniper green (primary): deep, botanical, calming.
        - Warm parchment (base): paper + linen.
        - Oxidized brass (accent): age + craft.
        - Charcoal ink (type): contrast without harshness.

        **Typography direction**
        - Display: a high-contrast serif that feels editorial (think “magazine cover,” not “wedding invite”).
        - Body: a neutral sans with great rhythm and legibility.
        - Supporting: monospace or condensed sans for “atlas” details (coordinates, room numbers, timestamps).

        If you want the vibe in one sentence: *a contemporary travel journal that someone cared enough to bind.*
        """),
      ]),

      Self.user("demo.long.user.2", """
      Love it. Now give me the four poster concepts and make them feel like they’re part of one system.

      Constraints:
      - each poster needs a short headline + 2–4 lines of supporting copy
      - each should have a different “scene” (lobby, room, café, neighborhood walk)
      - keep the copy calm; no “discover,” no “unforgettable,” no exclamation points
      """),

      Self.assistant("demo.long.assistant.2", parts: [
        Self.text("demo.long.assistant.2.text.1", """
        Here are four posters that behave like a set: same typographic cadence, same restraint, different scenes. I’ll write them so they can sit under photography or illustration.

        ---
        ### Poster 1 — Lobby (arrival)
        **Headline:** *Arrive quietly.*
        **Copy:**
        A soft landing after the day.
        Brass light, paper maps, a chair that waits.
        Check in like you’ve been here before.

        ---
        ### Poster 2 — Room (interior)
        **Headline:** *Make room for morning.*
        **Copy:**
        Linen, shade, and a window that opens.
        A desk for notes you’ll actually keep.
        Coffee nearby. Time unhurried.

        ---
        ### Poster 3 — Café (ritual)
        **Headline:** *Small rituals, held well.*
        **Copy:**
        Espresso, warm bread, the hum of pages turning.
        Sit at the counter or disappear into a corner.
        Stay as long as you need.

        ---
        ### Poster 4 — Neighborhood walk (place)
        **Headline:** *Walk the edges of the day.*
        **Copy:**
        Side streets, trees, late light.
        A pocket of calm between plans.
        Come back with something simple to say.
        """),
        Self.text("demo.long.assistant.2.text.2", """
        **System notes (so they feel like one family)**
        - Headline length: 2–5 words, sentence case, no punctuation.
        - Copy block: 3 lines, each under ~40 characters if possible.
        - A small “atlas line” can live at the bottom: *JUNIPER ATLAS · LOBBY · 07:18* (scene + time as a motif).
        """),
      ]),

      Self.user("demo.long.user.3", """
      Nice. Can you generate placeholder images for each poster? I want to see tool calls in the conversation.

      The “images” can be whatever you have in the demo assets—just pretend the tool made them and return the right result object.
      """),

      Self.assistant("demo.long.assistant.3", parts: [
        Self.text("demo.long.assistant.3.text.1", """
        I’ll generate four placeholder images (one per poster) using an image tool. Each tool call includes the prompt + returns an asset-backed “image” result.
        """),
        Self.toolImage(
          toolCallID: "demo.long.tool.image.1",
          title: "generate_image",
          prompt: "Hotel lobby, juniper green + warm brass, editorial photo, soft morning light, calm, minimal people",
          assetName: "image1"
        ),
        Self.toolImage(
          toolCallID: "demo.long.tool.image.2",
          title: "generate_image",
          prompt: "Hotel room interior, linen textures, window light, warm parchment tones, modern editorial photography",
          assetName: "image2"
        ),
        Self.toolImage(
          toolCallID: "demo.long.tool.image.3",
          title: "generate_image",
          prompt: "Boutique hotel cafe, espresso ritual, wood + paper, cozy corners, calm, shallow depth of field",
          assetName: "image3"
        ),
        Self.toolImage(
          toolCallID: "demo.long.tool.image.4",
          title: "generate_image",
          prompt: "Neighborhood walk, side street trees, twilight, cinematic but understated, juniper green accents",
          assetName: "image4"
        ),
        Self.text("demo.long.assistant.3.text.2", """
        If you want, next I can format these into a consistent poster layout (type scale + grid) and add an “atlas line” pattern for all four.
        """),
      ]),

      Self.user("demo.long.user.4", """
      Before layout, can you write longer body copy for a landing page? Keep the same tone.

      I want 3 sections:
      - “The hotel”
      - “The café”
      - “The neighborhood”

      Each section should be 2 paragraphs, around 80–120 words each.
      """),

      Self.assistant("demo.long.assistant.4", parts: [
        Self.text("demo.long.assistant.4.text.1", """
        ## The hotel
        *The Juniper Atlas* is a place designed for people who notice materials and remember light. The lobby is quiet in the morning and softly alive at night—brass glow, paper maps, the comfort of corners that don’t ask you to perform. Rooms are calm rather than sparse: linen you can feel, wood that carries warmth, and a desk that makes it easy to put a thought somewhere safe.

        The details are intentional without being precious. You’ll find good hooks where you want them, a chair that sits where the view makes sense, and a pace that feels human. It’s not a hotel that tries to impress you in one glance. It’s a hotel that earns you back over a few hours, the way a favorite book does.
        """),
        Self.text("demo.long.assistant.4.text.2", """
        ## The café
        The café is built around small rituals done well. Espresso pulled with patience, bread warmed until it smells like the start of a day, and a counter where the barista remembers your rhythm without turning it into a scene. Sit close to the windows for morning light, or take the seat that feels like it was meant for reading.

        It’s a room that holds people gently—conversation can happen here, but silence fits just as easily. The menu stays tight on purpose. A few things made with care, repeated until they’re right. It’s the kind of café you return to because it makes time feel better, not because it gives you something to post.
        """),
        Self.text("demo.long.assistant.4.text.3", """
        ## The neighborhood
        Outside, the neighborhood is walkable in the best way: side streets, trees, and late light that makes the edges of buildings soft. You can step out for ten minutes and come back with a small story—a corner shop, a bench with a view, the quiet of a residential block before dinner.

        The Juniper Atlas doesn’t treat the city like a checklist. It treats it like a series of moments you can actually inhabit. Ask for a route, not a list. We’ll point you to places that feel like they’ve always been there, and we’ll tell you when to go so the street sounds right. You’ll return to the hotel with something simple to say.
        """),
      ]),

      Self.user("demo.long.user.5", """
      Can we also show a few more image tool calls to make the demo feel “busy”?

      Maybe: a map detail, a brass fixture close-up, and a neighborhood texture shot.
      """),

      Self.assistant("demo.long.assistant.5", parts: [
        Self.text("demo.long.assistant.5.text.1", """
        Yep—three more quick tool calls, framed as “supporting assets” you might use for the landing page or the poster backgrounds.
        """),
        Self.toolImage(
          toolCallID: "demo.long.tool.image.5",
          title: "generate_image",
          prompt: "Vintage paper map detail, soft shadows, warm parchment, macro photo, editorial",
          assetName: "image2"
        ),
        Self.toolImage(
          toolCallID: "demo.long.tool.image.6",
          title: "generate_image",
          prompt: "Brass fixture close-up, warm reflections, shallow depth of field, minimal, premium craft",
          assetName: "image1"
        ),
        Self.toolImage(
          toolCallID: "demo.long.tool.image.7",
          title: "generate_image",
          prompt: "Neighborhood texture: painted wood, trees, sidewalk detail, late light, calm cinematic grain",
          assetName: "image4"
        ),
        Self.text("demo.long.assistant.5.text.2", """
        If you later swap these placeholders for real photos, the system still holds: calm headlines, short copy blocks, and a consistent palette doing most of the “branding” work.
        """),
      ]),

      Self.user("demo.long.user.6", """
      One more batch: I want the conversation to feel *very* tool-heavy.

      Can you generate a few more supporting images (patterns, signage, stationery, and a “room key” detail)?
      """),

      Self.assistant("demo.long.assistant.6", parts: [
        Self.text("demo.long.assistant.6.text.1", """
        Adding five more supporting assets. Same idea: prompt in, placeholder image out.
        """),
        Self.toolImage(
          toolCallID: "demo.long.tool.image.8",
          title: "generate_image",
          prompt: "Hotel stationery flatlay, paper texture, minimal typography, juniper green ink, brass clip, editorial",
          assetName: "image3"
        ),
        Self.toolImage(
          toolCallID: "demo.long.tool.image.9",
          title: "generate_image",
          prompt: "Wayfinding signage mock, serif + sans pairing, warm parchment background, calm, premium, minimal",
          assetName: "image4"
        ),
        Self.toolImage(
          toolCallID: "demo.long.tool.image.10",
          title: "generate_image",
          prompt: "Subtle botanical pattern tile, juniper branch linework, monochrome green on parchment, soft grain",
          assetName: "image2"
        ),
        Self.toolImage(
          toolCallID: "demo.long.tool.image.11",
          title: "generate_image",
          prompt: "Room key detail, brass key tag, engraved number, linen surface, warm shadows, macro photo",
          assetName: "image1"
        ),
        Self.toolImage(
          toolCallID: "demo.long.tool.image.12",
          title: "generate_image",
          prompt: "Lobby vignette: book, matchbox, map corner, brass pen, juniper sprig, calm editorial styling",
          assetName: "image1"
        ),
        Self.text("demo.long.assistant.6.text.2", """
        If you want the UI to show a neat grid for these later, we can also emit a “gallery” tool result format (array of assets) and render it as a single card.
        """),
      ]),
    ]
  }

  nonisolated private static func user(_ id: String, _ text: String) -> ChatMessage {
    ChatMessage(
      id: id,
      role: .user,
      parts: [
        .text(.init(id: "\(id).text", text: text, state: .done)),
      ]
    )
  }

  nonisolated private static func assistant(_ id: String, parts: [ChatMessagePart]) -> ChatMessage {
    ChatMessage(
      id: id,
      role: .assistant,
      parts: parts
    )
  }

  nonisolated private static func text(_ id: String, _ text: String) -> ChatMessagePart {
    .text(.init(id: id, text: text, state: .done))
  }

  nonisolated private static func toolImage(
    toolCallID: String,
    title: String,
    prompt: String,
    assetName: String
  ) -> ChatMessagePart {
    .tool(.init(
      toolCallID: toolCallID,
      toolName: "generate_image",
      title: title,
      input: .object([
        "prompt": .string(prompt),
        "size": .string("1024x1024"),
        "style": .string("editorial"),
      ]),
      output: .object([
        "type": .string("image"),
        "assetName": .string(assetName),
        "mediaType": .string("image/jpeg"),
      ]),
      state: .outputAvailable(preliminary: false)
    ))
  }
}
