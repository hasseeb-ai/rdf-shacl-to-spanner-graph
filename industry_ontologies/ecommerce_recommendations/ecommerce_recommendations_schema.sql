-- =============================================================================
-- GOOGLE CLOUD SPANNER PHYSICAL RELATIONAL SCHEMA (DDL)
-- Pattern: Table-Per-Concrete-Class with Flattened Superclass Hierarchies
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Taxonomy: Categories (Supports Transitive Subcategories)
-- -----------------------------------------------------------------------------
CREATE TABLE Categories (
  CategoryId STRING(36) NOT NULL,
  CategoryName STRING(MAX),
  ParentCategoryId STRING(36),
  CONSTRAINT FK_Categories_ParentCategory FOREIGN KEY (ParentCategoryId) REFERENCES Categories (CategoryId)
) PRIMARY KEY (CategoryId);

-- -----------------------------------------------------------------------------
-- 2. User Taxonomy: Customers & Merchants (Disjoint Classes inheriting User)
-- Top-Down Flattening: userId, userName flattened into leaf concrete tables
-- -----------------------------------------------------------------------------
CREATE TABLE Customers (
  UserId STRING(36) NOT NULL,
  UserName STRING(MAX)
) PRIMARY KEY (UserId);

CREATE TABLE Merchants (
  UserId STRING(36) NOT NULL,
  UserName STRING(MAX)
) PRIMARY KEY (UserId);

-- -----------------------------------------------------------------------------
-- 3. Product Taxonomy: Books, Electronics, Clothing (Disjoint Concrete Classes)
-- Top-Down Flattening: productPrice, CategoryId flattened into leaf concrete tables
-- -----------------------------------------------------------------------------
CREATE TABLE Books (
  ProductId STRING(36) NOT NULL,
  ProductPrice NUMERIC,
  CategoryId STRING(36),
  CONSTRAINT FK_Books_Category FOREIGN KEY (CategoryId) REFERENCES Categories (CategoryId)
) PRIMARY KEY (ProductId);

CREATE TABLE Electronics (
  ProductId STRING(36) NOT NULL,
  ProductPrice NUMERIC,
  CategoryId STRING(36),
  CONSTRAINT FK_Electronics_Category FOREIGN KEY (CategoryId) REFERENCES Categories (CategoryId)
) PRIMARY KEY (ProductId);

CREATE TABLE Clothing (
  ProductId STRING(36) NOT NULL,
  ProductPrice NUMERIC,
  CategoryId STRING(36),
  CONSTRAINT FK_Clothing_Category FOREIGN KEY (CategoryId) REFERENCES Categories (CategoryId)
) PRIMARY KEY (ProductId);

-- -----------------------------------------------------------------------------
-- 4. Transactional Entities: Orders & Reviews
-- HighRatingReview mapped as a STORED Generated Column (Equivalent Class)
-- -----------------------------------------------------------------------------
CREATE TABLE Orders (
  OrderId STRING(36) NOT NULL,
  CustomerId STRING(36) NOT NULL,
  OrderDate TIMESTAMP,
  CONSTRAINT FK_Orders_Customer FOREIGN KEY (CustomerId) REFERENCES Customers (UserId)
) PRIMARY KEY (OrderId);

CREATE TABLE Reviews (
  ReviewId STRING(36) NOT NULL,
  CustomerId STRING(36) NOT NULL,
  ProductId STRING(36) NOT NULL,
  RatingValue INT64,
  ReviewText STRING(MAX),
  IsHighRatingReview BOOL AS (RatingValue >= 4) STORED,
  CONSTRAINT FK_Reviews_Customer FOREIGN KEY (CustomerId) REFERENCES Customers (UserId)
) PRIMARY KEY (ReviewId);

-- -----------------------------------------------------------------------------
-- 5. Associative Relationship Tables
-- -----------------------------------------------------------------------------
-- Order -> Product containment (ex:orderContains)
CREATE TABLE OrderProducts (
  OrderId STRING(36) NOT NULL,
  ProductId STRING(36) NOT NULL,
  CONSTRAINT FK_OrderProducts_Order FOREIGN KEY (OrderId) REFERENCES Orders (OrderId)
) PRIMARY KEY (OrderId, ProductId);

-- Symmetric Recommendation Link (ex:frequentlyBoughtWith)
CREATE TABLE ProductRecommendations (
  ProductId STRING(36) NOT NULL,
  RecommendedProductId STRING(36) NOT NULL
) PRIMARY KEY (ProductId, RecommendedProductId);


-- =============================================================================
-- GOOGLE CLOUD SPANNER PROPERTY GRAPH SCHEMA
-- =============================================================================
CREATE PROPERTY GRAPH EcommerceGraph
  NODE TABLES (
    -- User Hierarchy Nodes
    Customers
      LABEL Customer PROPERTIES (UserId, UserName)
      LABEL User PROPERTIES (UserId, UserName),
    Merchants
      LABEL Merchant PROPERTIES (UserId, UserName)
      LABEL User PROPERTIES (UserId, UserName),

    -- Product Hierarchy Nodes
    Books
      LABEL Book PROPERTIES (ProductId, ProductPrice)
      LABEL Product PROPERTIES (ProductId, ProductPrice),
    Electronics
      LABEL Electronics PROPERTIES (ProductId, ProductPrice)
      LABEL Product PROPERTIES (ProductId, ProductPrice),
    Clothing
      LABEL Clothing PROPERTIES (ProductId, ProductPrice)
      LABEL Product PROPERTIES (ProductId, ProductPrice),

    -- Category Hierarchy Nodes
    Categories
      LABEL Category PROPERTIES (CategoryId, CategoryName),

    -- Order & Review Nodes
    Orders
      LABEL `Order` PROPERTIES (OrderId, OrderDate),
    Reviews
      LABEL Review PROPERTIES (ReviewId, RatingValue, ReviewText, IsHighRatingReview)
      LABEL HighRatingReview PROPERTIES (ReviewId, RatingValue, ReviewText, IsHighRatingReview)
  )
  EDGE TABLES (
    -- Customer -> Order (ex:placedOrder)
    Orders AS PlacedOrders
      SOURCE KEY (CustomerId) REFERENCES Customers (UserId)
      DESTINATION KEY (OrderId) REFERENCES Orders (OrderId)
      LABEL PLACED_ORDER NO PROPERTIES,

    -- Order -> Product Polymorphic Edges (ex:orderContains)
    OrderProducts AS OrderBooks
      SOURCE KEY (OrderId) REFERENCES Orders (OrderId)
      DESTINATION KEY (ProductId) REFERENCES Books (ProductId)
      LABEL ORDER_CONTAINS NO PROPERTIES,
    OrderProducts AS OrderElectronics
      SOURCE KEY (OrderId) REFERENCES Orders (OrderId)
      DESTINATION KEY (ProductId) REFERENCES Electronics (ProductId)
      LABEL ORDER_CONTAINS NO PROPERTIES,
    OrderProducts AS OrderClothing
      SOURCE KEY (OrderId) REFERENCES Orders (OrderId)
      DESTINATION KEY (ProductId) REFERENCES Clothing (ProductId)
      LABEL ORDER_CONTAINS NO PROPERTIES,

    -- Review -> Customer (ex:reviewedBy)
    Reviews AS ReviewAuthors
      SOURCE KEY (ReviewId) REFERENCES Reviews (ReviewId)
      DESTINATION KEY (CustomerId) REFERENCES Customers (UserId)
      LABEL REVIEWED_BY NO PROPERTIES,

    -- Review -> Product Polymorphic Edges (ex:reviewFor)
    Reviews AS ReviewBooks
      SOURCE KEY (ReviewId) REFERENCES Reviews (ReviewId)
      DESTINATION KEY (ProductId) REFERENCES Books (ProductId)
      LABEL REVIEW_FOR NO PROPERTIES,
    Reviews AS ReviewElectronics
      SOURCE KEY (ReviewId) REFERENCES Reviews (ReviewId)
      DESTINATION KEY (ProductId) REFERENCES Electronics (ProductId)
      LABEL REVIEW_FOR NO PROPERTIES,
    Reviews AS ReviewClothing
      SOURCE KEY (ReviewId) REFERENCES Reviews (ReviewId)
      DESTINATION KEY (ProductId) REFERENCES Clothing (ProductId)
      LABEL REVIEW_FOR NO PROPERTIES,

    -- Product -> Category (ex:hasCategory)
    Books AS BookCategories
      SOURCE KEY (ProductId) REFERENCES Books (ProductId)
      DESTINATION KEY (CategoryId) REFERENCES Categories (CategoryId)
      LABEL HAS_CATEGORY NO PROPERTIES,
    Electronics AS ElectronicsCategories
      SOURCE KEY (ProductId) REFERENCES Electronics (ProductId)
      DESTINATION KEY (CategoryId) REFERENCES Categories (CategoryId)
      LABEL HAS_CATEGORY NO PROPERTIES,
    Clothing AS ClothingCategories
      SOURCE KEY (ProductId) REFERENCES Clothing (ProductId)
      DESTINATION KEY (CategoryId) REFERENCES Categories (CategoryId)
      LABEL HAS_CATEGORY NO PROPERTIES,

    -- Transitive & Inverse Category Hierarchy (ex:subCategoryOf & ex:parentCategoryOf)
    Categories AS SubCategoryEdges
      SOURCE KEY (CategoryId) REFERENCES Categories (CategoryId)
      DESTINATION KEY (ParentCategoryId) REFERENCES Categories (CategoryId)
      LABEL SUB_CATEGORY_OF NO PROPERTIES,
    Categories AS ParentCategoryEdges
      SOURCE KEY (ParentCategoryId) REFERENCES Categories (CategoryId)
      DESTINATION KEY (CategoryId) REFERENCES Categories (CategoryId)
      LABEL PARENT_CATEGORY_OF NO PROPERTIES,

    -- Symmetric Recommendation Cross-Product Edges (ex:frequentlyBoughtWith)
    ProductRecommendations AS RecBooksBooks
      SOURCE KEY (ProductId) REFERENCES Books (ProductId)
      DESTINATION KEY (RecommendedProductId) REFERENCES Books (ProductId)
      LABEL FREQUENTLY_BOUGHT_WITH NO PROPERTIES,
    ProductRecommendations AS RecBooksElectronics
      SOURCE KEY (ProductId) REFERENCES Books (ProductId)
      DESTINATION KEY (RecommendedProductId) REFERENCES Electronics (ProductId)
      LABEL FREQUENTLY_BOUGHT_WITH NO PROPERTIES,
    ProductRecommendations AS RecBooksClothing
      SOURCE KEY (ProductId) REFERENCES Books (ProductId)
      DESTINATION KEY (RecommendedProductId) REFERENCES Clothing (ProductId)
      LABEL FREQUENTLY_BOUGHT_WITH NO PROPERTIES,
    ProductRecommendations AS RecElectronicsElectronics
      SOURCE KEY (ProductId) REFERENCES Electronics (ProductId)
      DESTINATION KEY (RecommendedProductId) REFERENCES Electronics (ProductId)
      LABEL FREQUENTLY_BOUGHT_WITH NO PROPERTIES,
    ProductRecommendations AS RecElectronicsBooks
      SOURCE KEY (ProductId) REFERENCES Electronics (ProductId)
      DESTINATION KEY (RecommendedProductId) REFERENCES Books (ProductId)
      LABEL FREQUENTLY_BOUGHT_WITH NO PROPERTIES,
    ProductRecommendations AS RecElectronicsClothing
      SOURCE KEY (ProductId) REFERENCES Electronics (ProductId)
      DESTINATION KEY (RecommendedProductId) REFERENCES Clothing (ProductId)
      LABEL FREQUENTLY_BOUGHT_WITH NO PROPERTIES,
    ProductRecommendations AS RecClothingClothing
      SOURCE KEY (ProductId) REFERENCES Clothing (ProductId)
      DESTINATION KEY (RecommendedProductId) REFERENCES Clothing (ProductId)
      LABEL FREQUENTLY_BOUGHT_WITH NO PROPERTIES,
    ProductRecommendations AS RecClothingBooks
      SOURCE KEY (ProductId) REFERENCES Clothing (ProductId)
      DESTINATION KEY (RecommendedProductId) REFERENCES Books (ProductId)
      LABEL FREQUENTLY_BOUGHT_WITH NO PROPERTIES,
    ProductRecommendations AS RecClothingElectronics
      SOURCE KEY (ProductId) REFERENCES Clothing (ProductId)
      DESTINATION KEY (RecommendedProductId) REFERENCES Electronics (ProductId)
      LABEL FREQUENTLY_BOUGHT_WITH NO PROPERTIES
  );