# Inline Tool Rendering Demo

This demo showcases how AIKit can render interactive UI components inline within chat messages, creating a more dynamic and interactive user experience.

## Features Demonstrated

### 1. **Interactive Navigation Tools**
- AI can render navigation buttons that route users to different app sections
- Buttons for Settings, Profile, and Dashboard with proper navigation handling
- Real sheet presentations and navigation state management

### 2. **UI Component Rendering**
- Interactive buttons, toggles, and sliders rendered inline
- Component interactions trigger feedback messages
- Demonstrates how AI can create functional UI elements

### 3. **Action Cards**
- Progress-based action cards with call-to-action buttons
- Shows completion status and allows user interaction
- Perfect for onboarding flows and task completion

### 4. **Progress Indicators**
- Animated progress bars showing task completion
- Real-time updates with percentage display
- Visual feedback for long-running operations

## Implementation Architecture

### Tool Definition Pattern
```swift
struct NavigationTool {
    static func createTool() -> Tool {
        Tool(
            type: .function,
            function: ToolFunction(
                name: "render_navigation",
                description: "Render interactive navigation UI",
                parameters: .object(properties: [
                    "destinations": .array(items: .string())
                ], required: ["destinations"])
            ),
            execute: { toolCall in
                // Tool execution logic
                return ToolResult.success(...)
            }
        )
    }
}
```

### Inline Rendering Pattern
```swift
struct InlineToolCallView: View {
    let toolCall: ToolCall
    let onNavigate: (String) -> Void
    let onAction: (String) -> Void
    
    @ViewBuilder
    private func renderToolUI() -> some View {
        switch toolCall.function.name {
        case "render_navigation":
            NavigationUIView(onNavigate: onNavigate)
        case "render_ui_component":
            UIComponentView(onAction: onAction)
        // ... other tool UIs
        }
    }
}
```

## Usage Examples

### Navigation Example
**User**: "Show me navigation options"
**AI**: "I'll display some navigation options for you." 
*[Renders interactive navigation UI with buttons for Settings, Profile, Dashboard]*

### UI Components Example
**User**: "Create some interactive UI components"
**AI**: "Here are some interactive UI components you can try:"
*[Renders buttons, toggles, sliders that respond to user interaction]*

### Action Cards Example
**User**: "Display a progress card"
**AI**: "Here's an action card showing your profile completion progress:"
*[Renders progress card with completion percentage and action button]*

## Key Benefits

1. **Enhanced User Experience**: Interactive elements provide immediate feedback
2. **Contextual Actions**: Tools can guide users to relevant app sections
3. **Rich Interactions**: Beyond text, AI can create functional UI elements
4. **Seamless Integration**: Tools integrate naturally with chat flow
5. **Extensible Architecture**: Easy to add new interactive tool types

## Technical Implementation

### Message Flow
1. User sends message requesting interactive UI
2. AI model calls appropriate tool function
3. Tool execution returns success with description
4. UI renders custom view based on tool type
5. User interacts with rendered components
6. Actions trigger navigation or feedback messages

### State Management
- Navigation state handled through SwiftUI's sheet presentation
- Tool interactions trigger callback functions
- Chat state updated through AIKit's message system
- Component state managed locally within tool views

## Extending the System

To add new interactive tools:

1. **Create Tool Definition**: Define the tool function and parameters
2. **Implement Tool UI**: Create SwiftUI view for the tool's interface
3. **Add Rendering Logic**: Update `renderToolUI()` to handle new tool type
4. **Handle Interactions**: Implement callback functions for user actions

This pattern enables unlimited expansion of interactive AI capabilities within chat interfaces.