import Foundation

// Models

struct FlashCard: Codable, Identifiable {
    var id = UUID()
    let front: String          // Word or phrase in target language
    let back: String           // Translation or meaning
    var difficulty: Int        // 1-5 scale, 1 = easiest, 5 = hardest
    var nextReviewDate: Date   // When to review this card next
    var reviewCount: Int       // Number of times reviewed
    var consecutiveCorrect: Int // Number of consecutive correct answers
    var lastReviewed: Date?    // When this card was last reviewed
    var notes: String?         // Optional notes about the word/phrase
    
    init(front: String, back: String, difficulty: Int = 3, notes: String? = nil) {
        self.front = front
        self.back = back
        self.difficulty = difficulty
        self.nextReviewDate = Date() // Start with now
        self.reviewCount = 0
        self.consecutiveCorrect = 0
        self.notes = notes
    }
}

// Deck for a specific language
struct Deck: Codable, Identifiable {
    var id = UUID()
    let name: String           // Deck name (e.g. "Spanish Basics")
    let targetLanguage: String // The language being learned
    let nativeLanguage: String // User's native language
    var cards: [FlashCard]     // The collection of flashcards
    let createdAt: Date        // When this deck was created
    var lastStudied: Date?     // When this deck was last studied
    
    init(name: String, targetLanguage: String, nativeLanguage: String) {
        self.name = name
        self.targetLanguage = targetLanguage
        self.nativeLanguage = nativeLanguage
        self.cards = []
        self.createdAt = Date()
    }
    
    // How many cards are due for review
    func dueCardCount() -> Int {
        return cards.filter { $0.nextReviewDate <= Date() }.count
    }
}

// Used to track a user's study session
struct StudySession {
    let deck: Deck
    let startTime: Date
    var endTime: Date?
    var cardsReviewed: Int = 0
    var correctResponses: Int = 0
    
    var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }
    
    var accuracyPercentage: Double {
        guard cardsReviewed > 0 else { return 0 }
        return Double(correctResponses) / Double(cardsReviewed) * 100
    }
}

// Spaced Repetition Algorithm

class SpacedRepetitionSystem {
    // The SuperMemo-2 algorithm for spaced repetition
    static func calculateNextReview(card: FlashCard, performanceRating: Int) -> Date {
        // Performance rating is 0-5, where:
        // 0-1: Completely forgot
        // 2-3: Remembered with difficulty
        // 4-5: Remembered easily
        
        let easeFactor = calculateEaseFactor(card: card, performanceRating: performanceRating)
        let interval = calculateInterval(card: card, performanceRating: performanceRating, easeFactor: easeFactor)
        
        // Calculate the next review date
        let nextDate = Calendar.current.date(byAdding: .day, value: interval, to: Date()) ?? Date()
        
        return nextDate
    }
    
    private static func calculateEaseFactor(card: FlashCard, performanceRating: Int) -> Double {
        // Base ease factor
        let baseEase = 2.5
        
        // Adjust based on current difficulty
        let difficultyAdjustment = Double(3 - card.difficulty) * 0.1
        
        // Adjust based on performance
        let performanceAdjustment = (Double(performanceRating) - 3.0) * 0.1
        
        // Calculate new ease factor (minimum 1.3)
        let easeFactor = max(1.3, baseEase + difficultyAdjustment + performanceAdjustment)
        
        return easeFactor
    }
    
    private static func calculateInterval(card: FlashCard, performanceRating: Int, easeFactor: Double) -> Int {
        // First time seeing the card
        if card.reviewCount == 0 {
            if performanceRating <= 2 {
                return 1  // Review tomorrow if struggled
            } else {
                return 2  // Review in 2 days if good recall
            }
        }
        
        // For subsequent reviews
        let currentInterval = Calendar.current.dateComponents([.day], from: card.lastReviewed ?? Date.distantPast, to: Date()).day ?? 1
        
        // If they completely forgot (rating 0-1), reset the interval
        if performanceRating <= 1 {
            return 1
        }
        
        // Calculate new interval based on ease factor
        let newInterval = Int(Double(currentInterval) * easeFactor)
        
        // Modify interval based on performance
        if performanceRating <= 2 {
            // Poor performance - reduce interval
            return max(1, Int(Double(newInterval) * 0.5))
        } else if performanceRating >= 4 {
            // Great performance - increase interval
            return Int(Double(newInterval) * 1.3)
        } else {
            // Average performance - use standard interval
            return newInterval
        }
    }
}

// Data Management

class LanguageLearningSystem {
    var decks: [Deck]
    private let fileManager = FileManager.default
    private let documentsURL: URL
    
    init() {
        // Set up file path for saving data
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Could not access documents directory")
        }
        documentsURL = documents.appendingPathComponent("language_learning_data.json")
        
        // Initialize decks first
        decks = []
        
        // THEN try to load existing decks
        if let loadedDecks = loadDecks() {
            decks = loadedDecks
        }
    }
    
    // Create a new deck
    func createDeck(name: String, targetLanguage: String, nativeLanguage: String) -> Deck {
        let newDeck = Deck(name: name, targetLanguage: targetLanguage, nativeLanguage: nativeLanguage)
        decks.append(newDeck)
        saveDecks()
        return newDeck
    }
    
    // Add a card to a deck
    func addCard(to deckIndex: Int, front: String, back: String, difficulty: Int = 3, notes: String? = nil) {
        guard deckIndex >= 0 && deckIndex < decks.count else {
            print("Invalid deck index")
            return
        }
        
        let newCard = FlashCard(front: front, back: back, difficulty: difficulty, notes: notes)
        decks[deckIndex].cards.append(newCard)
        saveDecks()
    }
    
    // Get cards due for review in a deck
    func getDueCards(from deckIndex: Int) -> [FlashCard] {
        guard deckIndex >= 0 && deckIndex < decks.count else {
            print("Invalid deck index")
            return []
        }
        
        let now = Date()
        return decks[deckIndex].cards.filter { $0.nextReviewDate <= now }
    }
    
    // Update a card after review
    func updateCardAfterReview(deckIndex: Int, cardID: UUID, performanceRating: Int, isCorrect: Bool) {
        guard deckIndex >= 0 && deckIndex < decks.count else {
            print("Invalid deck index")
            return
        }
        
        guard let cardIndex = decks[deckIndex].cards.firstIndex(where: { $0.id == cardID }) else {
            print("Card not found")
            return
        }
        
        // Update card properties
        var updatedCard = decks[deckIndex].cards[cardIndex]
        updatedCard.reviewCount += 1
        updatedCard.lastReviewed = Date()
        
        if isCorrect {
            updatedCard.consecutiveCorrect += 1
        } else {
            updatedCard.consecutiveCorrect = 0
        }
        
        // Adjust difficulty based on performance
        if performanceRating <= 1 {
            updatedCard.difficulty = min(5, updatedCard.difficulty + 1)
        } else if performanceRating >= 4 {
            updatedCard.difficulty = max(1, updatedCard.difficulty - 1)
        }
        
        // Calculate next review date
        updatedCard.nextReviewDate = SpacedRepetitionSystem.calculateNextReview(
            card: updatedCard,
            performanceRating: performanceRating
        )
        
        // Save the updated card
        decks[deckIndex].cards[cardIndex] = updatedCard
        decks[deckIndex].lastStudied = Date()
        saveDecks()
    }
    
    // Load decks from file
    private func loadDecks() -> [Deck]? {
        do {
            guard fileManager.fileExists(atPath: documentsURL.path) else {
                return nil
            }
            
            let data = try Data(contentsOf: documentsURL)
            let decoder = JSONDecoder()
            let loadedDecks = try decoder.decode([Deck].self, from: data)
            return loadedDecks
        } catch {
            print("Error loading decks: \(error)")
            return nil
        }
    }
    
    // Save decks to file
    private func saveDecks() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(decks)
            try data.write(to: documentsURL)
        } catch {
            print("Error saving decks: \(error)")
        }
    }
}

// User Interface

class LanguageLearningInterface {
    private let system = LanguageLearningSystem()
    
    func start() {
        printWelcome()
        
        var running = true
        while running {
            printMainMenu()
            if let choice = readLine() {
                switch choice {
                case "1":
                    createNewDeck()
                case "2":
                    viewDecks()
                case "3":
                    addCardToDeck()
                case "4":
                    studyDeck()
                case "5":
                    viewStatistics()
                case "6":
                    running = false
                    print("Goodbye! Good luck with your learning!")
                default:
                    print("Invalid choice. Please try again.")
                }
            }
        }
    }
    
    private func printWelcome() {
        print("""
        ================================================
                   LANGUAGE LEARNING TOOL 
        ================================================
        """)
    }
    
    private func printMainMenu() {
        print("""
        
        MAIN MENU:
        1. Create a new deck
        2. View all decks
        3. Add cards to a deck
        4. Study a deck
        5. View statistics
        6. Exit
        
        Choose an option:
        """, terminator: " ")
    }
    
    private func createNewDeck() {
        print("\n=== CREATE NEW DECK ===")
        
        print("Enter deck name:", terminator: " ")
        guard let name = readLine(), !name.isEmpty else {
            print("Deck name cannot be empty.")
            return
        }
        
        print("Enter target language:", terminator: " ")
        guard let targetLanguage = readLine(), !targetLanguage.isEmpty else {
            print("Target language cannot be empty.")
            return
        }
        
        print("Enter your native language:", terminator: " ")
        guard let nativeLanguage = readLine(), !nativeLanguage.isEmpty else {
            print("Native language cannot be empty.")
            return
        }
        
        let _ = system.createDeck(name: name, targetLanguage: targetLanguage, nativeLanguage: nativeLanguage)
        print("\nDeck '\(name)' has been created!")
    }
    
    private func viewDecks() {
        print("\n=== YOUR DECKS ===")
        
        if system.decks.isEmpty {
            print("You don't have any decks yet. Create one to get started!")
            return
        }
        
        for (index, deck) in system.decks.enumerated() {
            let dueCards = deck.dueCardCount()
            print("\(index + 1). \(deck.name) (\(deck.targetLanguage) / \(deck.nativeLanguage))")
            print("   Total cards: \(deck.cards.count), Due for review: \(dueCards)")
            
            if let lastStudied = deck.lastStudied {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                print("   Last studied: \(formatter.string(from: lastStudied))")
            } else {
                print("   Not studied yet")
            }
            print("")
        }
    }
    
    private func addCardToDeck() {
        if system.decks.isEmpty {
            print("\nYou need to create a deck first!")
            return
        }
        
        print("\n=== ADD CARDS TO DECK ===")
        viewDecks()
        
        print("Select deck (enter number):", terminator: " ")
        guard let deckInput = readLine(),
              let deckNumber = Int(deckInput),
              deckNumber > 0,
              deckNumber <= system.decks.count else {
            print("Invalid deck selection.")
            return
        }
        
        let deckIndex = deckNumber - 1
        let selectedDeck = system.decks[deckIndex]
        print("\nAdding cards to '\(selectedDeck.name)'")
        
        var addingCards = true
        while addingCards {
            print("\nEnter word or phrase in \(selectedDeck.targetLanguage):", terminator: " ")
            guard let front = readLine(), !front.isEmpty else {
                print("Word/phrase cannot be empty.")
                continue
            }
            
            print("Enter translation in \(selectedDeck.nativeLanguage):", terminator: " ")
            guard let back = readLine(), !back.isEmpty else {
                print("Translation cannot be empty.")
                continue
            }
            
            print("Enter difficulty level (1-5, where 1 is easiest, default is 3):", terminator: " ")
            let difficultyInput = readLine()
            let difficulty: Int
            if let input = difficultyInput, let value = Int(input), value >= 1, value <= 5 {
                difficulty = value
            } else {
                difficulty = 3 // Default difficulty
            }
            
            print("Enter any notes (optional):", terminator: " ")
            let notes = readLine()
            
            system.addCard(to: deckIndex, front: front, back: back, difficulty: difficulty, notes: notes)
            print("Card has been added!")
            
            print("\nAdd another card? (y/n):", terminator: " ")
            let continueInput = readLine()?.lowercased()
            addingCards = continueInput == "y" || continueInput == "yes"
        }
    }
    
    private func studyDeck() {
        if system.decks.isEmpty {
            print("\nYou need to create a deck first!")
            return
        }
        
        print("\n=== STUDY DECK ===")
        viewDecks()
        
        print("Select deck to study (enter number):", terminator: " ")
        guard let deckInput = readLine(),
              let deckNumber = Int(deckInput),
              deckNumber > 0,
              deckNumber <= system.decks.count else {
            print("Invalid deck selection.")
            return
        }
        
        let deckIndex = deckNumber - 1
        let selectedDeck = system.decks[deckIndex]
        
        let dueCards = system.getDueCards(from: deckIndex)
        if dueCards.isEmpty {
            print("\nNo cards are due for review in this deck!")
            print("Would you like to study new cards? (y/n):", terminator: " ")
            let newCardsInput = readLine()?.lowercased()
            if newCardsInput != "y" && newCardsInput != "yes" {
                return
            }
            
            // Get cards that haven't been reviewed yet
            let newCards = selectedDeck.cards.filter { $0.reviewCount == 0 }
            if newCards.isEmpty {
                print("\nNo new cards available. Add some cards first!")
                return
            }
            
            studyCards(deckIndex: deckIndex, cards: newCards)
        } else {
            print("\nYou have \(dueCards.count) cards due for review!")
            studyCards(deckIndex: deckIndex, cards: dueCards)
        }
    }
    
    private func studyCards(deckIndex: Int, cards: [FlashCard]) {
        var session = StudySession(
            deck: system.decks[deckIndex],
            startTime: Date()
        )
        
        var cardsToStudy = cards
        
        print("\nStudy session started for '\(session.deck.name)'")
        print("Cards to review: \(cardsToStudy.count)")
        print("Press Enter to begin...", terminator: "")
        _ = readLine()
        
        // Shuffle cards for better learning
        cardsToStudy.shuffle()
        
        for card in cardsToStudy {
            print("\n------------------------------------------------")
            // Show the native language word first
            print("\(session.deck.nativeLanguage): \(card.back)")
            
            // Prompt user to write the target language word
            print("\nWrite the word in \(session.deck.targetLanguage):", terminator: " ")
            let userInput = readLine() ?? ""
            
            // Show the correct answer
            print("\nCorrect answer: \(card.front)")
            
            // Check if user's answer matches the correct answer (case insensitive)
            let isExactMatch = userInput.lowercased() == card.front.lowercased()
            print(isExactMatch ? "Correct!" : "Not quite right.")
            
            if let notes = card.notes, !notes.isEmpty {
                print("Notes: \(notes)")
            }
            
            print("\nHow well did you do? (0-5)")
            print("0: Completely wrong")
            print("1: Mostly wrong")
            print("2: Partially correct")
            print("3: Mostly correct with mistakes")
            print("4: Almost perfect")
            print("5: Perfect")
            print("Your rating:", terminator: " ")
            
            var performanceRating = 3 // Default middle value
            if let ratingInput = readLine(), let rating = Int(ratingInput), rating >= 0, rating <= 5 {
                performanceRating = rating
            }
            
            let isCorrect = performanceRating >= 3
            
            system.updateCardAfterReview(
                deckIndex: deckIndex,
                cardID: card.id,
                performanceRating: performanceRating,
                isCorrect: isCorrect
            )
            
            session.cardsReviewed += 1
            if isCorrect {
                session.correctResponses += 1
            }
            
            // Show a brief progress indicator
            print("\nProgress: \(session.cardsReviewed)/\(cardsToStudy.count) cards reviewed")
        }
        
        // Complete the session
        session.endTime = Date()
        
        // Show session summary
        print("\n=== SESSION SUMMARY ===")
        print("Cards reviewed: \(session.cardsReviewed)")
        print("Correct responses: \(session.correctResponses)")
        print("Accuracy: \(String(format: "%.1f", session.accuracyPercentage))%")
        
        if let duration = session.duration {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            print("Time spent: \(minutes)m \(seconds)s")
        }
        
        print("\nGreat job! Keep it up!")
    }
    
    private func viewStatistics() {
        if system.decks.isEmpty {
            print("\nYou don't have any decks yet!")
            return
        }
        
        print("\n=== YOUR LEARNING STATISTICS ===")
        
        for (index, deck) in system.decks.enumerated() {
            print("\n\(index + 1). \(deck.name) (\(deck.targetLanguage))")
            print("   Total cards: \(deck.cards.count)")
            
            // Calculate cards by difficulty level
            let difficultyDistribution = [1, 2, 3, 4, 5].map { difficulty in
                deck.cards.filter { $0.difficulty == difficulty }.count
            }
            
            print("   Difficulty distribution:")
            for (level, count) in difficultyDistribution.enumerated() {
                let percentage = deck.cards.isEmpty ? 0 : Double(count) / Double(deck.cards.count) * 100
                print("     Level \(level + 1): \(count) cards (\(String(format: "%.1f", percentage))%)")
            }
            
            // Mastery progress
            let masteredCards = deck.cards.filter { $0.consecutiveCorrect >= 3 }.count
            let masteryPercentage = deck.cards.isEmpty ? 0 : Double(masteredCards) / Double(deck.cards.count) * 100
            print("   Mastery progress: \(masteredCards)/\(deck.cards.count) cards (\(String(format: "%.1f", masteryPercentage))%)")
            
            // Due cards
            let dueCards = deck.dueCardCount()
            print("   Cards due for review: \(dueCards)")
            
            if let lastStudied = deck.lastStudied {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
                print("   Last studied: \(formatter.string(from: lastStudied))")
            }
        }
    }
}

// Run the application
let app = LanguageLearningInterface()
app.start()
