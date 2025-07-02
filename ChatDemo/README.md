# AIChat Demo App

A comprehensive demonstration of the AIChat functionality - the Swift equivalent of Vercel AI SDK's `useChat` hook.

## 🎯 What This Demo Shows

This SwiftUI app demonstrates all the key features of the AIChat implementation:

### 1. **Basic Chat Demo** (`BasicChatDemoView`)
- **@UseChat property wrapper** usage
- **Real-time messaging** with mock responses
- **Status indicators** (ready, streaming, error)
- **Message history** management
- **Clean SwiftUI integration**

**Key Features Shown:**
- Reactive `@Published` properties
- Message state management
- Automatic UI updates
- Input handling and submission

### 2. **Chat with Tools Demo** (`ToolChatDemoView`)
- **Tool integration** with existing AIKit Tool system
- **Automatic tool execution** during conversations
- **Visual tool call indicators**
- **Multiple tool types**: Weather, Calculator, Current Time

**Key Features Shown:**
- Tool definition and execution
- Tool call visualization
- Seamless tool integration
- Tool result display

### 3. **File Attachments Demo** (`AttachmentChatDemoView`)
- **Image upload** and display
- **File attachment** support
- **Multi-media messages**
- **Attachment management**

**Key Features Shown:**
- Image picker integration
- Attachment visualization
- Mixed content messages
- File handling

### 4. **Persistent Chat Demo** (`PersistentChatDemoView`)
- **Auto-save functionality** using `chatAutosave` modifier
- **Manual save/load** operations
- **Markdown export** capability
- **Message metadata** display

**Key Features Shown:**
- Data persistence
- Export functionality
- Message statistics
- State restoration

### 5. **Custom Styled Chat** (`CustomStyledChatView`)
- **5 Beautiful themes**: Default, Ocean, Forest, Sunset, Dark
- **Custom UI components**
- **Animated interactions**
- **Theme switching**

**Key Features Shown:**
- UI customization
- Theme system
- Custom animations
- Visual polish

### 6. **Message Management Demo** (`MessageManagementDemoView`)
- **Edit messages** in-place
- **Delete messages** from history
- **Add system messages**
- **Message statistics**

**Key Features Shown:**
- Message manipulation
- Conversation control
- Role-based styling
- Context menus

### 7. **Error Handling Demo** (`ErrorHandlingDemoView`)
- **Error simulation** (Network, Timeout, API errors)
- **Graceful error recovery**
- **Retry mechanisms**
- **Error state management**

**Key Features Shown:**
- Robust error handling
- User-friendly error messages
- Recovery options
- Error state indicators

### 8. **Streaming Control Demo** (`StreamingControlDemoView`)
- **Real-time streaming** visualization
- **Stream control** (pause, stop, resume)
- **Performance metrics** (characters, timing)
- **Interactive controls**

**Key Features Shown:**
- Streaming management
- Real-time feedback
- Performance monitoring
- Stream customization

## 🚀 How to Run the Demo

### Prerequisites
- Xcode 15.0+
- iOS 16.0+ or macOS 13.0+
- Swift 5.9+

### Steps
1. **Open the project:**
   ```bash
   cd /Users/juan/Developer/ai-kit/ChatDemo
   open ChatDemo.xcodeproj
   ```

2. **Build and run:**
   - Select your target device/simulator
   - Press `Cmd+R` to build and run

3. **Explore the demos:**
   - Navigate through the main menu
   - Try each demo feature
   - Experiment with different scenarios

## 🏗️ Architecture Highlights

### AIChat Integration
The demos showcase how AIChat integrates seamlessly with SwiftUI:

```swift
@UseChat(model: mockProvider.languageModel("gpt-4o-mini")) var chat

var body: some View {
    VStack {
        ForEach(chat.messages) { message in
            MessageView(message: message)
        }
        
        ChatInput(chat: chat)
    }
    .chatAutosave(chat, key: "demo-chat")
}
```

### Key Components
- **@UseChat** - Property wrapper for SwiftUI integration
- **AIChat** - Core chat management class
- **ChatMessage** - Message data structure
- **ChatStatus** - State management
- **Tool integration** - Existing AIKit Tool system
- **Persistence** - Auto-save and manual save/load

### Mock Provider Usage
All demos use `MockProvider` for testing without requiring real API keys:

```swift
// Simulates realistic AI responses
MockProvider().languageModel("gpt-4o-mini")
```

## 📱 Demo Screenshots

Each demo shows different aspects:

1. **Basic Chat** - Clean, minimal interface
2. **Tools** - Visual tool execution indicators  
3. **Attachments** - File upload and display
4. **Persistence** - Save/load/export controls
5. **Custom Styles** - Beautiful themes and animations
6. **Management** - Message editing and deletion
7. **Error Handling** - Graceful error states
8. **Streaming** - Real-time text streaming

## 🔧 Customization

The demos are designed to be:
- **Modular** - Each demo can be used independently
- **Extensible** - Easy to add new features
- **Configurable** - Multiple settings and options
- **Reusable** - Components can be extracted for other projects

## 🎯 Production Ready

This implementation provides:
- **Type safety** with Swift's type system
- **Concurrency safety** with @MainActor isolation
- **Error handling** with comprehensive error states
- **Performance** with efficient streaming and updates
- **Accessibility** with proper SwiftUI patterns
- **Testing** with mock providers

The AIChat system is ready for production use in real SwiftUI applications!