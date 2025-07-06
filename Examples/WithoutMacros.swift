import AIKit

// Example: Using AIKit without macros
// Only import AIKit - no macro dependency required

struct Person: SchemaProviding {
    let name: String
    let age: Int
    
    // Manual schema definition
    static var schema: ObjectSchema<Person> {
        ObjectSchema.define(
            name: "Person",
            description: "A person with basic information"
        ) {
            Schema.string("name", description: "Full name", minLength: 1)
            Schema.integer("age", description: "Age in years", range: 0...150)
        }
    }
    
    // Manual Partial type for streaming
    struct Partial {
        let name: String?
        let age: Int?
    }
}

// Usage is the same
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