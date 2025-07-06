import AIKit
import AIKitMacro

// Example: Using AIKit with macros
// Import both AIKit and AIKitMacro for macro functionality

@AIModel
struct Person {
    @Field("Full name", minLength: 1)
    let name: String
    
    @Field("Age in years", range: 0...150)
    let age: Int
}

// Usage is exactly the same!
func example() async throws {
    let client = AIClient()
    let model = client.provider.openai.languageModel("gpt-4o-mini")
    
    let person = try await client.generateObject(
        model,
        prompt: "Generate a person",
        type: Person.self
    )
    
    print("Generated: \(person.object.name), age \(person.object.age)")
}