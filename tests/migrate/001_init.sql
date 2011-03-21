BEGIN_SETUP:


CREATE TABLE [dbo].[customer](
	[id] [int] IDENTITY(1,1) NOT NULL
		CONSTRAINT [PK_customer] PRIMARY KEY,
	[display_name] [varchar](128) NULL,
	[email] [varchar](128) NOT NULL,
	[password_hash] [varchar](512) NULL,
	[password_salt] [varchar](128) NULL,
	[plan_sku] [varchar](64) NULL,
	[enable_ads] [bit] NOT NULL
		CONSTRAINT [DF_customer_enable_ads] DEFAULT (0),
	[max_ledgers] [int] NOT NULL
		CONSTRAINT [DF_customer_max_ledgers] DEFAULT (1),
	[auth_token] [varchar](64) NULL,
	[created_at] [datetime] NULL,
	[updated_at] [datetime] NULL
)
GO


CREATE TABLE [dbo].[category](
	[id] [int] IDENTITY(1,1) NOT NULL
		CONSTRAINT [PK_category] PRIMARY KEY,
	[name] [varchar](128) NOT NULL,
	[customer_id] [int] NOT NULL
)
GO


CREATE TABLE [dbo].[data_import](
	[id] [int] IDENTITY(1,1) NOT NULL
		CONSTRAINT [PK_data_import] PRIMARY KEY,
	[total_tx] [int] NOT NULL
		CONSTRAINT [DF_data_import_total_tx] DEFAULT (0),
	[ledger_id] [int] NULL,
	[created_by] [int] NULL,
	[created_at] [datetime] NULL
)
GO


CREATE TABLE [dbo].[ledger](
	[id] [int] IDENTITY(1,1) NOT NULL
		CONSTRAINT [PK_ledger] PRIMARY KEY,
	[name] [varchar](128) NOT NULL,
	[balance] [decimal](10, 2) NOT NULL
		CONSTRAINT [DF_ledger_balance] DEFAULT (0),
	[owner] [int] NOT NULL,
	[created_by] [int] NULL,
	[updated_by] [int] NULL,
	[created_at] [datetime] NULL,
	[updated_at] [datetime] NULL,
)
GO


CREATE TABLE [dbo].[tx](
	[id] [int] IDENTITY(1,1) NOT NULL
		CONSTRAINT [PK_tx] PRIMARY KEY,
	[tx_date] [datetime] NOT NULL,
	[tx_type] [varchar](32) NULL,
	[check_num] [varchar](32) NULL,
	[payee] [varchar](128) NULL,
	[memo] [varchar](512) NULL,
	[amount] [decimal](10, 2) NOT NULL
		CONSTRAINT [DF_tx_amount] DEFAULT (0),
	[status] [varchar](32) NULL,
	[update_summary] [varchar](4000) NULL,
	[created_by] [int] NULL,
	[updated_by] [int] NULL,
	[category_id] [int] NULL,
	[ledger_id] [int] NOT NULL,
	[data_import_id] [int] NULL,
	[created_at] [datetime] NULL,
	[updated_at] [datetime] NULL
)
GO


CREATE TABLE [dbo].[tx_split](
	[id] [int] IDENTITY(1,1) NOT NULL
		CONSTRAINT [PK_tx_split] PRIMARY KEY,
	[amount] [decimal](10, 2) NOT NULL
		CONSTRAINT [DF_tx_split_amount] DEFAULT (0),
	[memo] [varchar](512) NULL,
	[category_id] [int] NULL,
	[tx_id] [int] NULL,
	[created_at] [datetime] NULL,
	[updated_at] [datetime] NULL
)
GO


END_SETUP:


BEGIN_TEARDOWN:

/* DROP [dbo].[tx_split] */
ALTER TABLE [dbo].[tx_split] DROP CONSTRAINT [DF_tx_split_amount]
GO

DROP TABLE [dbo].[tx_split]
GO


/* DROP [dbo].[tx] */
ALTER TABLE [dbo].[tx] DROP CONSTRAINT [DF_tx_amount]
GO

DROP TABLE [dbo].[tx]
GO


/* DROP [dbo].[ledger] */
ALTER TABLE [dbo].[ledger] DROP CONSTRAINT [DF_ledger_balance]
GO

DROP TABLE [dbo].[ledger]
GO


/* DROP [dbo].[data_import] */
ALTER TABLE [dbo].[data_import] DROP CONSTRAINT [DF_data_import_total_tx]
GO

DROP TABLE [dbo].[data_import]
GO


/* DROP [dbo].[customer] */
ALTER TABLE [dbo].[customer] DROP CONSTRAINT [DF_customer_enable_ads]
GO

ALTER TABLE [dbo].[customer] DROP CONSTRAINT [DF_customer_max_ledgers]
GO

DROP TABLE [dbo].[customer]
GO


/* DROP [dbo].[category] */
DROP TABLE [dbo].[category]
GO


END_TEARDOWN: