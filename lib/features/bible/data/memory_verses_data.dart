class MemoryVerse {
  final String reference;
  final String text;
  final String category;

  const MemoryVerse({
    required this.reference,
    required this.text,
    required this.category,
  });
}

const memoryVerses = <MemoryVerse>[
  // FAITH
  MemoryVerse(reference: 'Hebrews 11:1', text: 'Now faith is confidence in what we hope for and assurance about what we do not see.', category: 'Faith'),
  MemoryVerse(reference: '2 Corinthians 5:7', text: 'For we live by faith, not by sight.', category: 'Faith'),
  MemoryVerse(reference: 'Matthew 17:20', text: 'Truly I tell you, if you have faith as small as a mustard seed, you can say to this mountain, "Move from here to there," and it will move. Nothing will be impossible for you.', category: 'Faith'),
  MemoryVerse(reference: 'Mark 11:24', text: 'Therefore I tell you, whatever you ask for in prayer, believe that you have received it, and it will be yours.', category: 'Faith'),
  MemoryVerse(reference: 'Romans 10:17', text: 'Consequently, faith comes from hearing the message, and the message is heard through the word about Christ.', category: 'Faith'),
  MemoryVerse(reference: 'James 1:6', text: 'But when you ask, you must believe and not doubt, because the one who doubts is like a wave of the sea, blown and tossed by the wind.', category: 'Faith'),
  MemoryVerse(reference: 'John 20:29', text: 'Then Jesus told him, "Because you have seen me, you have believed; blessed are those who have not seen and yet have believed."', category: 'Faith'),
  MemoryVerse(reference: 'Mark 9:23', text: '"Everything is possible for one who believes."', category: 'Faith'),
  MemoryVerse(reference: 'Hebrews 11:6', text: 'And without faith it is impossible to please God, because anyone who comes to him must believe that he exists and that he rewards those who earnestly seek him.', category: 'Faith'),
  MemoryVerse(reference: '1 John 5:4', text: 'For everyone born of God overcomes the world. This is the victory that has overcome the world, even our faith.', category: 'Faith'),
  MemoryVerse(reference: 'Luke 1:37', text: 'For no word from God will ever fail.', category: 'Faith'),
  MemoryVerse(reference: 'Matthew 21:22', text: 'If you believe, you will receive whatever you ask for in prayer.', category: 'Faith'),

  // HOPE
  MemoryVerse(reference: 'Jeremiah 29:11', text: 'For I know the plans I have for you, declares the LORD, plans to prosper you and not to harm you, plans to give you hope and a future.', category: 'Hope'),
  MemoryVerse(reference: 'Romans 15:13', text: 'May the God of hope fill you with all joy and peace as you trust in him, so that you may overflow with hope by the power of the Holy Spirit.', category: 'Hope'),
  MemoryVerse(reference: 'Psalm 42:5', text: 'Why, my soul, are you downcast? Why so disturbed within me? Put your hope in God, for I will yet praise him, my Savior and my God.', category: 'Hope'),
  MemoryVerse(reference: 'Psalm 62:5', text: 'Yes, my soul, find rest in God; my hope comes from him.', category: 'Hope'),
  MemoryVerse(reference: 'Psalm 71:5', text: 'For you have been my hope, Sovereign LORD, my confidence since my youth.', category: 'Hope'),
  MemoryVerse(reference: 'Psalm 33:22', text: 'May your unfailing love be with us, LORD, even as we put our hope in you.', category: 'Hope'),
  MemoryVerse(reference: 'Psalm 130:5', text: 'I wait for the LORD, my whole being waits, and in his word I put my hope.', category: 'Hope'),
  MemoryVerse(reference: 'Romans 8:24-25', text: 'For in this hope we were saved. But hope that is seen is no hope at all. Who hopes for what they already have? But if we hope for what we do not yet have, we wait for it patiently.', category: 'Hope'),
  MemoryVerse(reference: 'Psalm 39:7', text: 'But now, Lord, what do I look for? My hope is in you.', category: 'Hope'),
  MemoryVerse(reference: 'Psalm 119:114', text: 'You are my hiding place and my shield; I hope in your word.', category: 'Hope'),
  MemoryVerse(reference: 'Isaiah 40:31', text: 'But those who hope in the LORD will renew their strength. They will soar on wings like eagles; they will run and not grow weary, they will walk and not be faint.', category: 'Hope'),

  // LOVE
  MemoryVerse(reference: 'John 3:16', text: 'For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life.', category: 'Love'),
  MemoryVerse(reference: '1 Corinthians 13:4-5', text: 'Love is patient, love is kind. It does not envy, it does not boast, it is not proud. It does not dishonor others, it is not self-seeking, it is not easily angered, it keeps no record of wrongs.', category: 'Love'),
  MemoryVerse(reference: '1 John 4:8', text: 'Whoever does not love does not know God, because God is love.', category: 'Love'),
  MemoryVerse(reference: 'Romans 8:35-39', text: 'Who shall separate us from the love of Christ? Shall trouble or hardship or persecution or famine or nakedness or danger or sword? ... For I am convinced that neither death nor life, neither angels nor demons, neither the present nor the future, nor any powers, neither height nor depth, nor anything else in all creation, will be able to separate us from the love of God that is in Christ Jesus our Lord.', category: 'Love'),
  MemoryVerse(reference: '1 John 4:19', text: 'We love because he first loved us.', category: 'Love'),
  MemoryVerse(reference: '1 Peter 4:8', text: 'Above all, love each other deeply, because love covers over a multitude of sins.', category: 'Love'),
  MemoryVerse(reference: 'John 15:13', text: 'Greater love has no one than this: to lay down one\'s life for one\'s friends.', category: 'Love'),
  MemoryVerse(reference: 'Romans 5:8', text: 'But God demonstrates his own love for us in this: While we were still sinners, Christ died for us.', category: 'Love'),
  MemoryVerse(reference: '1 Corinthians 16:14', text: 'Do everything in love.', category: 'Love'),
  MemoryVerse(reference: 'Ephesians 4:2-3', text: 'Be completely humble and gentle; be patient, bearing with one another in love. Make every effort to keep the unity of the Spirit through the bond of peace.', category: 'Love'),
  MemoryVerse(reference: 'Colossians 3:14', text: 'And over all these virtues put on love, which binds them all together in perfect unity.', category: 'Love'),
  MemoryVerse(reference: '1 John 4:11', text: 'Dear friends, since God so loved us, we also ought to love one another.', category: 'Love'),

  // PRAYER
  MemoryVerse(reference: 'Philippians 4:6-7', text: 'Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God. And the peace of God, which transcends all understanding, will guard your hearts and your minds in Christ Jesus.', category: 'Prayer'),
  MemoryVerse(reference: 'Matthew 6:9-13', text: 'This, then, is how you should pray: "Our Father in heaven, hallowed be your name, your kingdom come, your will be done, on earth as it is in heaven. Give us today our daily bread. And forgive us our debts, as we also have forgiven our debtors. And lead us not into temptation, but deliver us from the evil one."', category: 'Prayer'),
  MemoryVerse(reference: '1 Thessalonians 5:16-18', text: 'Rejoice always, pray continually, give thanks in all circumstances; for this is God\'s will for you in Christ Jesus.', category: 'Prayer'),
  MemoryVerse(reference: 'Matthew 7:7', text: 'Ask and it will be given to you; seek and you will find; knock and the door will be opened to you.', category: 'Prayer'),
  MemoryVerse(reference: 'James 5:16', text: 'Therefore confess your sins to each other and pray for each other so that you may be healed. The prayer of a righteous person is powerful and effective.', category: 'Prayer'),
  MemoryVerse(reference: 'Colossians 4:2', text: 'Devote yourselves to prayer, being watchful and thankful.', category: 'Prayer'),
  MemoryVerse(reference: 'Mark 11:25', text: 'And when you stand praying, if you hold anything against anyone, forgive them, so that your Father in heaven may forgive you your sins.', category: 'Prayer'),
  MemoryVerse(reference: 'Ephesians 6:18', text: 'And pray in the Spirit on all occasions with all kinds of prayers and requests. With this in mind, be alert and always keep on praying for all the Lord\'s people.', category: 'Prayer'),
  MemoryVerse(reference: 'Psalm 145:18', text: 'The LORD is near to all who call on him, to all who call on him in truth.', category: 'Prayer'),
  MemoryVerse(reference: 'Romans 12:12', text: 'Be joyful in hope, patient in affliction, faithful in prayer.', category: 'Prayer'),
  MemoryVerse(reference: 'Luke 18:1', text: 'Then Jesus told his disciples a parable to show them that they should always pray and not give up.', category: 'Prayer'),
  MemoryVerse(reference: '2 Chronicles 7:14', text: 'If my people, who are called by my name, will humble themselves and pray and seek my face and turn from their wicked ways, then I will hear from heaven, and I will forgive their sin and will heal their land.', category: 'Prayer'),

  // WISDOM
  MemoryVerse(reference: 'Proverbs 3:5-6', text: 'Trust in the LORD with all your heart and lean not on your own understanding; in all your ways submit to him, and he will make your paths straight.', category: 'Wisdom'),
  MemoryVerse(reference: 'Proverbs 4:7', text: 'The beginning of wisdom is this: Get wisdom. Though it cost all you have, get understanding.', category: 'Wisdom'),
  MemoryVerse(reference: 'Proverbs 1:7', text: 'The fear of the LORD is the beginning of knowledge, but fools despise wisdom and instruction.', category: 'Wisdom'),
  MemoryVerse(reference: 'Proverbs 9:10', text: 'The fear of the LORD is the beginning of wisdom, and knowledge of the Holy One is understanding.', category: 'Wisdom'),
  MemoryVerse(reference: 'James 1:5', text: 'If any of you lacks wisdom, you should ask God, who gives generously to all without finding fault, and it will be given to you.', category: 'Wisdom'),
  MemoryVerse(reference: 'Proverbs 2:6', text: 'For the LORD gives wisdom; from his mouth come knowledge and understanding.', category: 'Wisdom'),
  MemoryVerse(reference: 'Proverbs 12:15', text: 'The way of fools seems right to them, but the wise listen to advice.', category: 'Wisdom'),
  MemoryVerse(reference: 'Proverbs 16:16', text: 'How much better to get wisdom than gold, to get insight rather than silver!', category: 'Wisdom'),
  MemoryVerse(reference: 'Proverbs 10:14', text: 'The wise store up knowledge, but the mouth of a fool invites ruin.', category: 'Wisdom'),
  MemoryVerse(reference: 'Proverbs 11:2', text: 'When pride comes, then comes disgrace, but with humility comes wisdom.', category: 'Wisdom'),
  MemoryVerse(reference: 'Ecclesiastes 7:12', text: 'Wisdom is a shelter as money is a shelter, but the advantage of knowledge is this: Wisdom preserves those who have it.', category: 'Wisdom'),

  // PROMISES
  MemoryVerse(reference: 'Romans 8:28', text: 'And we know that in all things God works for the good of those who love him, who have been called according to his purpose.', category: 'Promises'),
  MemoryVerse(reference: 'Deuteronomy 31:6', text: 'Be strong and courageous. Do not be afraid or terrified because of them, for the LORD your God goes with you; he will never leave you nor forsake you.', category: 'Promises'),
  MemoryVerse(reference: 'Joshua 1:9', text: 'Have I not commanded you? Be strong and courageous. Do not be afraid; do not be discouraged, for the LORD your God will be with you wherever you go.', category: 'Promises'),
  MemoryVerse(reference: 'Isaiah 43:2', text: 'When you pass through the waters, I will be with you; and when you pass through the rivers, they will not sweep over you. When you walk through the fire, you will not be burned; the flames will not set you ablaze.', category: 'Promises'),
  MemoryVerse(reference: 'Psalm 121:3', text: 'He will not let your foot slip — he who watches over you will not slumber.', category: 'Promises'),
  MemoryVerse(reference: 'Psalm 34:10', text: 'The lions may grow weak and hungry, but those who seek the LORD lack no good thing.', category: 'Promises'),
  MemoryVerse(reference: 'Psalm 37:25', text: 'I was young and now I am old, yet I have never seen the righteous forsaken or their children begging bread.', category: 'Promises'),
  MemoryVerse(reference: 'Psalm 84:11', text: 'For the LORD God is a sun and shield; the LORD bestows favor and honor; no good thing does he withhold from those whose walk is blameless.', category: 'Promises'),
  MemoryVerse(reference: 'Philippians 4:19', text: 'And my God will meet all your needs according to the riches of his glory in Christ Jesus.', category: 'Promises'),
  MemoryVerse(reference: '1 Peter 5:7', text: 'Cast all your anxiety on him because he cares for you.', category: 'Promises'),
  MemoryVerse(reference: 'Psalm 23:6', text: 'Surely your goodness and love will follow me all the days of my life, and I will dwell in the house of the LORD forever.', category: 'Promises'),

  // SALVATION
  MemoryVerse(reference: 'Ephesians 2:8-9', text: 'For it is by grace you have been saved, through faith — and this is not from yourselves, it is the gift of God — not by works, so that no one can boast.', category: 'Salvation'),
  MemoryVerse(reference: 'Romans 10:9-10', text: 'If you declare with your mouth, "Jesus is Lord," and believe in your heart that God raised him from the dead, you will be saved. For it is with your heart that you believe and are justified, and it is with your mouth that you profess your faith and are saved.', category: 'Salvation'),
  MemoryVerse(reference: 'Acts 4:12', text: 'Salvation is found in no one else, for there is no other name under heaven given to mankind by which we must be saved.', category: 'Salvation'),
  MemoryVerse(reference: 'Titus 3:5', text: 'He saved us, not because of righteous things we had done, but because of his mercy. He saved us through the washing of rebirth and renewal by the Holy Spirit.', category: 'Salvation'),
  MemoryVerse(reference: 'Romans 6:23', text: 'For the wages of sin is death, but the gift of God is eternal life in Christ Jesus our Lord.', category: 'Salvation'),
  MemoryVerse(reference: '1 John 1:9', text: 'If we confess our sins, he is faithful and just and will forgive us our sins and purify us from all unrighteousness.', category: 'Salvation'),
  MemoryVerse(reference: 'Acts 16:31', text: 'They replied, "Believe in the Lord Jesus, and you will be saved — you and your household."', category: 'Salvation'),
  MemoryVerse(reference: 'John 10:9', text: 'I am the gate; whoever enters through me will be saved. They will come in and go out, and find pasture.', category: 'Salvation'),
  MemoryVerse(reference: 'Romans 5:1', text: 'Therefore, since we have been justified through faith, we have peace with God through our Lord Jesus Christ.', category: 'Salvation'),
  MemoryVerse(reference: '1 Timothy 2:5', text: 'For there is one God and one mediator between God and mankind, the man Christ Jesus.', category: 'Salvation'),
  MemoryVerse(reference: 'Hebrews 7:25', text: 'Therefore he is able to save completely those who come to God through him, because he always lives to intercede for them.', category: 'Salvation'),

  // WORSHIP
  MemoryVerse(reference: 'Psalm 95:6-7', text: 'Come, let us bow down in worship, let us kneel before the LORD our Maker; for he is our God and we are the people of his pasture, the flock under his care.', category: 'Worship'),
  MemoryVerse(reference: 'Psalm 100:1-2', text: 'Shout for joy to the LORD, all the earth. Worship the LORD with gladness; come into his presence with singing.', category: 'Worship'),
  MemoryVerse(reference: 'John 4:24', text: 'God is spirit, and his worshipers must worship in the Spirit and in truth.', category: 'Worship'),
  MemoryVerse(reference: 'Psalm 29:2', text: 'Ascribe to the LORD the glory due his name; worship the LORD in the splendor of his holiness.', category: 'Worship'),
  MemoryVerse(reference: 'Psalm 96:9', text: 'Worship the LORD in the splendor of his holiness; tremble before him, all the earth.', category: 'Worship'),
  MemoryVerse(reference: 'Psalm 34:1', text: 'I will extol the LORD at all times; his praise will always be on my lips.', category: 'Worship'),
  MemoryVerse(reference: 'Psalm 150:1-2', text: 'Praise the LORD. Praise God in his sanctuary; praise him in his mighty heavens. Praise him for his acts of power; praise him for his surpassing greatness.', category: 'Worship'),
  MemoryVerse(reference: 'Psalm 150:6', text: 'Let everything that has breath praise the LORD. Praise the LORD.', category: 'Worship'),
  MemoryVerse(reference: 'Psalm 103:1', text: 'Praise the LORD, my soul; all my inmost being, praise his holy name.', category: 'Worship'),
  MemoryVerse(reference: 'Hebrews 12:28', text: 'Therefore, since we are receiving a kingdom that cannot be shaken, let us be thankful, and so worship God acceptably with reverence and awe.', category: 'Worship'),
  MemoryVerse(reference: '1 Chronicles 16:29', text: 'Ascribe to the LORD the glory due his name. Bring an offering and come before him. Worship the LORD in the splendor of his holiness.', category: 'Worship'),

  // GRACE
  MemoryVerse(reference: '2 Corinthians 12:9', text: 'But he said to me, "My grace is sufficient for you, for my power is made perfect in weakness." Therefore I will boast all the more gladly about my weaknesses, so that Christ\'s power may rest on me.', category: 'Grace'),
  MemoryVerse(reference: 'James 4:6', text: 'But he gives us more grace. That is why Scripture says: "God opposes the proud but shows favor to the humble."', category: 'Grace'),
  MemoryVerse(reference: 'Romans 5:20-21', text: 'But where sin increased, grace increased all the more, so that, just as sin reigned in death, so also grace might reign through righteousness to bring eternal life through Jesus Christ our Lord.', category: 'Grace'),
  MemoryVerse(reference: 'Ephesians 1:7-8', text: 'In him we have redemption through his blood, the forgiveness of sins, in accordance with the riches of God\'s grace that he lavished on us.', category: 'Grace'),
  MemoryVerse(reference: 'Hebrews 4:16', text: 'Let us then approach God\'s throne of grace with confidence, so that we may receive mercy and find grace to help us in our time of need.', category: 'Grace'),
  MemoryVerse(reference: 'Titus 2:11', text: 'For the grace of God has appeared that offers salvation to all people.', category: 'Grace'),
  MemoryVerse(reference: '2 Timothy 1:9', text: 'He has saved us and called us to a holy life — not because of anything we have done but because of his own purpose and grace.', category: 'Grace'),
  MemoryVerse(reference: 'Ephesians 2:4-5', text: 'But because of his great love for us, God, who is rich in mercy, made us alive with Christ even when we were dead in transgressions — it is by grace you have been saved.', category: 'Grace'),
  MemoryVerse(reference: 'Acts 15:11', text: 'No! We believe it is through the grace of our Lord Jesus that we are saved, just as they are.', category: 'Grace'),
  MemoryVerse(reference: '1 Peter 5:10', text: 'And the God of all grace, who called you to his eternal glory in Christ, after you have suffered a little while, will himself restore you and make you strong, firm and steadfast.', category: 'Grace'),
  MemoryVerse(reference: 'Hebrews 13:9', text: 'It is good for our hearts to be strengthened by grace.', category: 'Grace'),

  // STRENGTH
  MemoryVerse(reference: 'Philippians 4:13', text: 'I can do all this through him who gives me strength.', category: 'Strength'),
  MemoryVerse(reference: 'Psalm 18:32', text: 'It is God who arms me with strength and keeps my way secure.', category: 'Strength'),
  MemoryVerse(reference: 'Nehemiah 8:10', text: 'The joy of the LORD is your strength.', category: 'Strength'),
  MemoryVerse(reference: 'Psalm 27:1', text: 'The LORD is my light and my salvation — whom shall I fear? The LORD is the stronghold of my life — of whom shall I be afraid?', category: 'Strength'),
  MemoryVerse(reference: 'Psalm 28:7', text: 'The LORD is my strength and my shield; my heart trusts in him, and he helps me.', category: 'Strength'),
  MemoryVerse(reference: 'Psalm 29:11', text: 'The LORD gives strength to his people; the LORD blesses his people with peace.', category: 'Strength'),
  MemoryVerse(reference: 'Psalm 73:26', text: 'My flesh and my heart may fail, but God is the strength of my heart and my portion forever.', category: 'Strength'),
  MemoryVerse(reference: 'Psalm 46:1', text: 'God is our refuge and strength, an ever-present help in trouble.', category: 'Strength'),
  MemoryVerse(reference: 'Isaiah 41:10', text: 'So do not fear, for I am with you; do not be dismayed, for I am your God. I will strengthen you and help you; I will uphold you with my righteous right hand.', category: 'Strength'),
  MemoryVerse(reference: 'Psalm 84:5', text: 'Blessed are those whose strength is in you, whose hearts are set on pilgrimage.', category: 'Strength'),
  MemoryVerse(reference: 'Psalm 118:14', text: 'The LORD is my strength and my defense; he has become my salvation.', category: 'Strength'),
  MemoryVerse(reference: 'Psalm 138:3', text: 'When I called, you answered me; you greatly emboldened me.', category: 'Strength'),
];
