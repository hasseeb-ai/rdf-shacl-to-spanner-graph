-- =============================================================================
-- PHYSICAL RELATIONAL SCHEMA (Google Cloud Spanner)
-- Pattern: Table-Per-Concrete-Class with Flattened Superclass Properties
-- =============================================================================

-- Concrete Class: ex:Movie (subclass of ex:CreativeWork)
CREATE TABLE Movies (
  MovieId STRING(36) NOT NULL,
  Title STRING(MAX),
  ReleaseDate DATE
) PRIMARY KEY (MovieId);

-- Concrete Class: ex:TVSeries (subclass of ex:CreativeWork)
CREATE TABLE TVSeries (
  TVSeriesId STRING(36) NOT NULL,
  Title STRING(MAX),
  ReleaseDate DATE
) PRIMARY KEY (TVSeriesId);

-- Concrete Class: ex:Actor (subclass of ex:RolePlayer)
CREATE TABLE Actors (
  ActorId STRING(36) NOT NULL,
  Name STRING(MAX)
) PRIMARY KEY (ActorId);

-- Concrete Class: ex:Director (subclass of ex:RolePlayer)
CREATE TABLE Directors (
  DirectorId STRING(36) NOT NULL,
  Name STRING(MAX)
) PRIMARY KEY (DirectorId);

-- Reified Object Property: ex:actedIn (Actor -> Movie)
CREATE TABLE ActorActedInMovies (
  ActorId STRING(36) NOT NULL,
  MovieId STRING(36) NOT NULL,
  CharacterName STRING(MAX),
  BillingOrder INT64,
  CONSTRAINT FK_ActedIn_Actor_Movie FOREIGN KEY (ActorId) REFERENCES Actors (ActorId),
  CONSTRAINT FK_ActedIn_Movie FOREIGN KEY (MovieId) REFERENCES Movies (MovieId)
) PRIMARY KEY (ActorId, MovieId);

-- Reified Object Property: ex:actedIn (Actor -> TVSeries)
CREATE TABLE ActorActedInTVSeries (
  ActorId STRING(36) NOT NULL,
  TVSeriesId STRING(36) NOT NULL,
  CharacterName STRING(MAX),
  BillingOrder INT64,
  CONSTRAINT FK_ActedIn_Actor_TVSeries FOREIGN KEY (ActorId) REFERENCES Actors (ActorId),
  CONSTRAINT FK_ActedIn_TVSeries FOREIGN KEY (TVSeriesId) REFERENCES TVSeries (TVSeriesId)
) PRIMARY KEY (ActorId, TVSeriesId);

-- Object Property: ex:directed (Director -> Movie)
CREATE TABLE DirectorDirectedMovies (
  DirectorId STRING(36) NOT NULL,
  MovieId STRING(36) NOT NULL,
  CONSTRAINT FK_Directed_Director_Movie FOREIGN KEY (DirectorId) REFERENCES Directors (DirectorId),
  CONSTRAINT FK_Directed_Movie FOREIGN KEY (MovieId) REFERENCES Movies (MovieId)
) PRIMARY KEY (DirectorId, MovieId);

-- Object Property: ex:directed (Director -> TVSeries)
CREATE TABLE DirectorDirectedTVSeries (
  DirectorId STRING(36) NOT NULL,
  TVSeriesId STRING(36) NOT NULL,
  CONSTRAINT FK_Directed_Director_TVSeries FOREIGN KEY (DirectorId) REFERENCES Directors (DirectorId),
  CONSTRAINT FK_Directed_TVSeries FOREIGN KEY (TVSeriesId) REFERENCES TVSeries (TVSeriesId)
) PRIMARY KEY (DirectorId, TVSeriesId);

-- =============================================================================
-- PROPERTY GRAPH SCHEMA (GoogleSQL / GQL)
-- =============================================================================

CREATE PROPERTY GRAPH EntertainmentGraph
  NODE TABLES (
    -- Movie Node Table with Concrete and Superclass Labels
    Movies
      LABEL Movie PROPERTIES (MovieId, Title, ReleaseDate)
      LABEL CreativeWork PROPERTIES (MovieId AS WorkId, Title, ReleaseDate),

    -- TVSeries Node Table with Concrete and Superclass Labels
    TVSeries
      LABEL TVSeries PROPERTIES (TVSeriesId, Title, ReleaseDate)
      LABEL CreativeWork PROPERTIES (TVSeriesId AS WorkId, Title, ReleaseDate),

    -- Actor Node Table with Concrete and Superclass Labels
    Actors
      LABEL Actor PROPERTIES (ActorId, Name)
      LABEL RolePlayer PROPERTIES (ActorId AS RolePlayerId, Name),

    -- Director Node Table with Concrete and Superclass Labels
    Directors
      LABEL Director PROPERTIES (DirectorId, Name)
      LABEL RolePlayer PROPERTIES (DirectorId AS RolePlayerId, Name)
  )
  EDGE TABLES (
    -- Actor -> Movie (actedIn)
    ActorActedInMovies
      SOURCE KEY (ActorId) REFERENCES Actors (ActorId)
      DESTINATION KEY (MovieId) REFERENCES Movies (MovieId)
      LABEL ACTED_IN PROPERTIES (CharacterName, BillingOrder),

    -- Actor -> TVSeries (actedIn)
    ActorActedInTVSeries
      SOURCE KEY (ActorId) REFERENCES Actors (ActorId)
      DESTINATION KEY (TVSeriesId) REFERENCES TVSeries (TVSeriesId)
      LABEL ACTED_IN PROPERTIES (CharacterName, BillingOrder),

    -- Director -> Movie (directed)
    DirectorDirectedMovies
      SOURCE KEY (DirectorId) REFERENCES Directors (DirectorId)
      DESTINATION KEY (MovieId) REFERENCES Movies (MovieId)
      LABEL DIRECTED NO PROPERTIES,

    -- Director -> TVSeries (directed)
    DirectorDirectedTVSeries
      SOURCE KEY (DirectorId) REFERENCES Directors (DirectorId)
      DESTINATION KEY (TVSeriesId) REFERENCES TVSeries (TVSeriesId)
      LABEL DIRECTED NO PROPERTIES
  );