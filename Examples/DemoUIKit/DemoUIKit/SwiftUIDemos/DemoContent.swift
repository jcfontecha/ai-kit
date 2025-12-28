import Foundation
import AIKit

enum DemoContent {
  nonisolated static var initialMessages: [ChatMessage] {
    [
      ChatMessage(
        id: "demo.user.prompt.1",
        role: .user,
        parts: [
          .text(.init(id: "demo.user.prompt.1.text", text: "Can you write 3 paragraphs about Animal Crossing?", state: .done)),
        ]
      ),
      ChatMessage(
        id: "demo.assistant.animal-crossing.1",
        role: .assistant,
        parts: [
          .text(.init(id: "demo.assistant.animal-crossing.1.text", text: animalCrossingP1, state: .done)),
        ]
      ),
      ChatMessage(
        id: "demo.assistant.animal-crossing.2",
        role: .assistant,
        parts: [
          .text(.init(id: "demo.assistant.animal-crossing.2.text", text: animalCrossingP2, state: .done)),
        ]
      ),
      ChatMessage(
        id: "demo.assistant.animal-crossing.3",
        role: .assistant,
        parts: [
          .text(.init(id: "demo.assistant.animal-crossing.3.text", text: animalCrossingP3, state: .done)),
        ]
      ),
    ]
  }

  nonisolated private static let animalCrossingP1: String = """
  Animal Crossing is at its best when you treat it like a tiny daily ritual instead of a game you “finish.” You check in, water a few flowers, talk to your neighbors, and do a lap around the island to see what changed overnight. The pace is intentionally gentle, and the fun comes from noticing small details—seasonal lighting, shop stock, a surprise visit from a villager, or a new message in the mailbox—rather than chasing a single objective. It’s the kind of game that rewards slowing down.
  """

  nonisolated private static let animalCrossingP2: String = """
  The island design loop is where it becomes personal. You start with rough paths and simple furniture, then gradually refine everything: terraform a hill to frame a view, move a house to open up a plaza, or build a cozy market street near Nook’s Cranny. It’s less about a “perfect” layout and more about creating spaces that feel lived-in—reading nooks, picnic spots, a cluttered workshop, a café corner—so walking around your island feels intentional.
  """

  nonisolated private static let animalCrossingP3: String = """
  And then there’s the social layer: neighbors who develop tiny running jokes, trading turnip prices, sending letters, and visiting friends’ islands for inspiration. Even when you’re playing solo, it still feels communal—like you’re part of a quiet town where everyone has their own routines. That gentle sense of connection is a big part of why the series feels comforting when you just want to unwind.
  """
}
