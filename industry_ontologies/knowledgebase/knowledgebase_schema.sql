-- =============================================================================
-- GOOGLE CLOUD SPANNER PHYSICAL RELATIONAL DDL
-- Table-Per-Concrete-Class Pattern with Flattened Inheritance and Constraints
-- =============================================================================

CREATE TABLE Authors (
  AuthorId STRING(36) NOT NULL,
  Username STRING(MAX)
) PRIMARY KEY (AuthorId);

CREATE TABLE Categories (
  CategoryId STRING(36) NOT NULL,
  CategoryName STRING(MAX),
  ParentCategoryId STRING(36),
  CONSTRAINT FK_Categories_ParentCategory FOREIGN KEY (ParentCategoryId) REFERENCES Categories (CategoryId)
) PRIMARY KEY (CategoryId);

CREATE TABLE Articles (
  ArticleId STRING(36) NOT NULL,
  Title STRING(MAX),
  WordCount INT64,
  AuthorId STRING(36) NOT NULL,
  CategoryId STRING(36) NOT NULL,
  ReferencedArticleId STRING(36),
  LinkedArticleId STRING(36),
  CONSTRAINT FK_Articles_Author FOREIGN KEY (AuthorId) REFERENCES Authors (AuthorId),
  CONSTRAINT FK_Articles_Category FOREIGN KEY (CategoryId) REFERENCES Categories (CategoryId),
  CONSTRAINT FK_Articles_ReferencedArticle FOREIGN KEY (ReferencedArticleId) REFERENCES Articles (ArticleId),
  CONSTRAINT FK_Articles_LinkedArticle FOREIGN KEY (LinkedArticleId) REFERENCES Articles (ArticleId)
) PRIMARY KEY (ArticleId);

-- =============================================================================
-- GOOGLE CLOUD SPANNER PROPERTY GRAPH DDL
-- Multi-label Inheritance Hierarchy & Edge Mappings
-- =============================================================================

CREATE PROPERTY GRAPH KnowledgebaseGraph
  NODE TABLES (
    Articles
      LABEL Article PROPERTIES (ArticleId, Title, WordCount)
      LABEL Entity NO PROPERTIES,
    Categories
      LABEL Category PROPERTIES (CategoryId, CategoryName)
      LABEL Entity NO PROPERTIES,
    Authors
      LABEL Author PROPERTIES (AuthorId, Username)
  )
  EDGE TABLES (
    Articles AS ArticleAuthors
      SOURCE KEY (ArticleId) REFERENCES Articles (ArticleId)
      DESTINATION KEY (AuthorId) REFERENCES Authors (AuthorId)
      LABEL HAS_AUTHOR NO PROPERTIES,
    Articles AS ArticleCategories
      SOURCE KEY (ArticleId) REFERENCES Articles (ArticleId)
      DESTINATION KEY (CategoryId) REFERENCES Categories (CategoryId)
      LABEL CATEGORIZED_UNDER NO PROPERTIES,
    Articles AS ArticleReferences
      SOURCE KEY (ArticleId) REFERENCES Articles (ArticleId)
      DESTINATION KEY (ReferencedArticleId) REFERENCES Articles (ArticleId)
      LABEL `REFERENCES` NO PROPERTIES,
    Articles AS ArticleLinks
      SOURCE KEY (ArticleId) REFERENCES Articles (ArticleId)
      DESTINATION KEY (LinkedArticleId) REFERENCES Articles (ArticleId)
      LABEL LINKED_WITH NO PROPERTIES,
    Categories AS CategorySubCategories
      SOURCE KEY (CategoryId) REFERENCES Categories (CategoryId)
      DESTINATION KEY (ParentCategoryId) REFERENCES Categories (CategoryId)
      LABEL SUB_CATEGORY_OF NO PROPERTIES
  );