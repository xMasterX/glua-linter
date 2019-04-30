{-# LANGUAGE FlexibleInstances,
             MultiParamTypeClasses #-}

module GLua.PSLexer where

import GLua.AG.Token

import Text.Parsec
import Text.Parsec.String
import Text.Parsec.Pos
import Text.ParserCombinators.UU.BasicInstances(LineColPos(..))

-- | Region start to SourcePos
rgStart2sp :: Region -> SourcePos
rgStart2sp (Region start _) = lcp2sp start

-- | Region end to SourcePos
rgEnd2sp :: Region -> SourcePos
rgEnd2sp (Region _ end) = lcp2sp end

-- | SourcePos to region
sp2Rg :: SourcePos -> Region
sp2Rg sp = Region (sp2lcp sp) (sp2lcp sp)

-- | LineColPos to SourcePos
lcp2sp :: LineColPos -> SourcePos
lcp2sp (LineColPos l c _) = newPos "source.lua" (l + 1) (c + 1)

-- | SourcePos to LineColPos
sp2lcp :: SourcePos -> LineColPos
sp2lcp pos = LineColPos (sourceLine pos - 1) (sourceColumn pos - 1) 0

-- | Get the source position
pPos :: Parser LineColPos
pPos = sp2lcp <$> getPosition

-- | Underscore character
underscore :: Parser Char
underscore = char '_'

-- | Parse the string until the end. Used in parseLineComment among others.
pUntilEnd :: Parser String
pUntilEnd = manyTill anyChar (lookAhead (endOfLine <|> const '\n' <$> eof))

-- | Whitespace parser.
parseWhitespace :: Parser String
parseWhitespace = many1 space <?> "whitespace"

-- | An escaped character of a single line string
-- Takes the delimiter of the string as parameter
escapedStringChar :: Char -> Parser String
escapedStringChar delim = (\c -> ['\\', c]) <$ char '\\' <*> noneOf ['\n'] <|> (:[]) <$> noneOf ['\n', delim]

-- | The start of a nested string
-- Returns the amount of =-signs at the start of the nested string
startNestedString :: Parser String
startNestedString = do
    _ <- char '['
    depth <- many (char '=')
    _ <- char '['
    return depth

-- | Parses a multiline string
-- returns the amount of =-signs in the string delimiter and the contents
nestedString :: String -> Parser String
nestedString depth = do
    let endStr = "]" ++ depth ++ "]"
    manyTill anyChar (try $ string endStr)

-- | Parse Lua style comments
parseLuaComment :: Parser Token
parseLuaComment = do
    _ <- string "--"
    -- When a nested comment is started, it must be finished
    startNested <- optionMaybe (try startNestedString)

    case startNested of
        Nothing -> DashComment <$> pUntilEnd
        Just depth -> do
            contents <- nestedString depth
            return $ DashBlockComment (length depth) contents


-- | Parse C-Style comments
parseCComment :: Parser Token
parseCComment = do
    _ <- char '/'
    try (SlashComment <$ char '/' <*> pUntilEnd) <|>
     SlashBlockComment <$ char '*' <*> manyTill anyChar (try (string "*/") <|> const "\n" <$> eof)

-- | Parse any kind of comment.
parseComment :: Parser Token
parseComment = parseLuaComment <|> parseCComment <?> "Comment"

-- | Convert the result of the nestedString parser to a MultiLine string
nestedStringToMLString :: String -> String -> Token
nestedStringToMLString depth contents = MLString (showChar '[' . showString depth . showChar '[' . showString contents . showChar ']' . showString depth . showChar ']' $ "")

-- | Parse single line strings e.g. "sdf", 'werf'.
parseLineString :: Char -> Parser String
parseLineString c = concat <$ char c <*> many (escapedStringChar c) <* char c

-- | Single and multiline strings.
parseString :: Parser Token
parseString = SQString <$> parseLineString '\'' <|>
              DQString <$> parseLineString '"' <|> do
                depth <- startNestedString
                nestedStringToMLString depth <$> nestedString depth <?> "String"

-- | Parse any kind of number.
-- Except for numbers that start with a '.'. That's handled by parseDots to solve ambiguity.
parseNumber :: Parser Token
parseNumber = TNumber <$> ((++) <$> (pHexadecimal <|> pNumber) <*> option "" parseNumberSuffix) <?> "Number"
    where
        pNumber :: Parser String
        pNumber = (++) <$> many1 digit <*> option "" pDecimal

        pDecimal :: Parser String
        pDecimal = (:) <$> char '.' <*> many digit

        pHexadecimal :: Parser String
        pHexadecimal = (++) <$> try (string "0x") <*> ((++) <$> many1 pHex <*> option "" pDecimal)

        pHex :: Parser Char
        pHex = digit <|> oneOf ['a', 'b', 'c', 'd', 'e', 'f', 'A', 'B', 'C', 'D', 'E', 'F']

-- Parse the suffix of a number
parseNumberSuffix :: Parser String
parseNumberSuffix = (\e s d -> e : s ++ d) <$> oneOf ['e', 'E', 'p', 'P']
            <*> option "" (string "+" <|> string "-")
            <*> many1 digit

-- | Parse either a keyword or an identifier that starts with that keyword
parseKeyword :: Token -> String -> Parser Token
parseKeyword tok str = try (do
    _ <- string str
    (\s -> Identifier (str ++ s)) <$> many1 (underscore <|> alphaNum) <|>
        return tok
    <?> "Keyword " ++ str)

-- | Parse just an identifier.
parseIdentifier :: Parser String
parseIdentifier = (:) <$> (letter <|> underscore) <*> many allowed <?> "Identifier"
    where
        allowed = letter <|> digit <|> underscore

-- | Parse a label.
parseLabel :: Parser String
parseLabel = string "::" *> parseIdentifier <* string "::" <?> "Label"

-- | Parse anything to do with dots. Indexaction (.), concatenation (..), varargs (...) or numbers that start with a dot
parseDots :: Parser Token
parseDots = do
    _ <- char '.' -- first .
    try (do
        _ <- char '.' -- second .
        try (VarArg <$ char '.') <|> -- third .
            return Concatenate) <|>

        -- try to parse a number that starts with a .
        try (do
            nums <- many1 digit
            suffix <- option "" parseNumberSuffix
            return $ TNumber ('.' : (nums ++ suffix))
            ) <|>


        return Dot

-- | Parse any kind of token.
parseToken :: Parser Token
parseToken =
                Whitespace <$> parseWhitespace                  <|>
                -- Constants
                try parseString                                 <|>
                parseNumber                                     <|>
                parseKeyword TTrue "true"                       <|>
                parseKeyword TFalse "false"                     <|>
                parseKeyword Nil "nil"                          <|>
                parseKeyword Not "not"                          <|>
                parseKeyword And "and"                          <|>
                parseKeyword Or "or"                            <|>
                parseKeyword Function "function"                <|>
                parseKeyword Local "local"                      <|>
                parseKeyword If "if"                            <|>
                parseKeyword Then "then"                        <|>
                parseKeyword Elseif "elseif"                    <|>
                parseKeyword Else "else"                        <|>
                parseKeyword For "for"                          <|>
                parseKeyword In "in"                            <|>
                parseKeyword Do "do"                            <|>
                parseKeyword While "while"                      <|>
                parseKeyword Until "until"                      <|>
                parseKeyword Repeat "repeat"                    <|>
                parseKeyword Continue "continue"                <|>
                parseKeyword Break "break"                      <|>
                parseKeyword Return "return"                    <|>
                parseKeyword End "end"                          <|>

                Identifier <$> parseIdentifier                  <|>

                Semicolon  <$ char ';'                          <|>
                parseDots                                       <|>

                try parseComment                                <|>

                -- Operators
                Plus <$ string "+"                              <|>
                Minus <$ string "-"                             <|>
                Multiply <$ string "*"                          <|>
                Divide <$ string "/"                            <|>
                Modulus <$ string "%"                           <|>
                Power <$ string "^"                             <|>
                TEq <$ try (string "==")                        <|>
                Equals <$ string "="                            <|>
                TNEq <$ string "~="                             <|>
                TCNEq <$ try (string "!=")                      <|>
                CNot <$ string "!"                              <|>
                TLEQ <$ try (string "<=")                       <|>
                TLT <$ string "<"                               <|>
                TGEQ <$ try (string ">=")                       <|>
                TGT <$ string ">"                               <|>
                Label <$> try parseLabel                        <|>
                Colon <$ string ":"                             <|>
                Comma <$ string ","                             <|>
                Hash <$ string "#"                              <|>
                CAnd <$ string "&&"                             <|>
                COr <$ string "||"                              <|>

                LRound <$ char '('                              <|>
                RRound <$ char ')'                              <|>
                LCurly <$ char '{'                              <|>
                RCurly <$ char '}'                              <|>
                LSquare <$ char '['                             <|>
                RSquare <$ char ']'


-- | A thing of which the region is to be parsed
annotated :: (Region -> a -> b) -> Parser a -> Parser b
annotated f p = (\s t e -> f (Region s e) t) <$> pPos <*> p <*> pPos

-- | parse located MToken
parseMToken :: Parser MToken
parseMToken =
  do
    start <- pPos
    tok <- parseToken
    end <- pPos

    return $ MToken (Region start end) tok

-- | Parse a list of tokens and turn them into MTokens.
parseTokens :: Parser [MToken]
parseTokens = many parseMToken

-- | Parse the potential #!comment on the first line
-- Lua ignores the first line if it starts with #
parseHashBang :: Parser String
parseHashBang = option "" (char '#' *> pUntilEnd)

-- | Parse a string into MTokens.
execParseTokens :: String -> Either ParseError [MToken]
execParseTokens = parse (parseHashBang *> parseTokens <* eof) "input"
