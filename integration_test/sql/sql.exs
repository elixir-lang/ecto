defmodule Ecto.Integration.SQLTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Barebone
  alias Ecto.Integration.Post
  alias Ecto.Integration.CorruptedPk
  import Ecto.Query, only: [from: 2]

  test "fragmented types" do
    datetime = ~N[2014-01-16 20:26:51.000000]
    TestRepo.insert!(%Post{inserted_at: datetime})
    query = from p in Post, where: fragment("? >= ?", p.inserted_at, ^datetime), select: p.inserted_at
    assert [^datetime] = TestRepo.all(query)
  end

  @tag :array_type
  test "fragment array types" do
    datetime1 = ~N[2014-01-16 00:00:00.0]
    datetime2 = ~N[2014-02-16 00:00:00.0]
    result = TestRepo.query!("SELECT $1::timestamp[]", [[datetime1, datetime2]])
    assert [[[{{2014, 1, 16}, _}, {{2014, 2, 16}, _}]]] = result.rows
  end

  test "math infix operations interoperability" do
    decimal_result = Decimal.new(2.0)

    # Single parameter

    assert %{rows: [[2]]} = TestRepo.query!("SELECT 1 + $1::integer", [1])
    assert %{rows: [[2.0]]} = TestRepo.query!("SELECT 1 + $1::float", [1])

    assert %{rows: [[result]]} = TestRepo.query!("SELECT 1 + $1::numeric", [1])
    assert Decimal.equal?(result, decimal_result)

    assert %{rows: [[result]]} = TestRepo.query!("SELECT 1 + $1::numeric", [Decimal.new(1)])
    assert Decimal.equal?(result, decimal_result)

    # Two parameters
    
    assert_raise Postgrex.Error, ~r/ambiguous_function/, fn ->
      TestRepo.query!("SELECT $1 + $2", [1, 2])
    end

    assert %{rows: [[2.0]]} = TestRepo.query!("SELECT $1::integer + $2::float", [1, 1.0])
    assert %{rows: [[^decimal_result]]} = TestRepo.query!("SELECT $1::integer + $2::numeric", [1, Decimal.new(1.0)])
    assert %{rows: [[2.0]]} = TestRepo.query!("SELECT $1::float + $2::numeric", [1.0, Decimal.new(1.0)])
    assert %{rows: [[2.0]]} = TestRepo.query!("SELECT $1::numeric + $2::float", [Decimal.new(1.0), 1.0])

    assert %{rows: [[0]]} = TestRepo.query!("SELECT $1::integer / $2::integer", [1, 2])
    assert %{rows: [[0.5]]} = TestRepo.query!("SELECT $1::integer / $2::float", [1, 2])
    
    assert %{rows: [[result]]} = TestRepo.query!("SELECT $1::numeric / $2::integer", [Decimal.new(4), 2])
    assert Decimal.equal?(result, decimal_result)
  end

  test "query!/4" do
    result = TestRepo.query!("SELECT 1")
    assert result.rows == [[1]]
  end

  test "to_sql/3" do
    {sql, []} = Ecto.Adapters.SQL.to_sql(:all, TestRepo, Barebone)
    assert sql =~ "SELECT"
    assert sql =~ "barebones"

    {sql, [0]} = Ecto.Adapters.SQL.to_sql(:update_all, TestRepo,
                                          from(b in Barebone, update: [set: [num: ^0]]))
    assert sql =~ "UPDATE"
    assert sql =~ "barebones"
    assert sql =~ "SET"

    {sql, []} = Ecto.Adapters.SQL.to_sql(:delete_all, TestRepo, Barebone)
    assert sql =~ "DELETE"
    assert sql =~ "barebones"
  end

  test "raises when primary key is not unique on struct operation" do
    schema = %CorruptedPk{a: "abc"}
    TestRepo.insert!(schema)
    TestRepo.insert!(schema)
    TestRepo.insert!(schema)

    assert_raise Ecto.MultiplePrimaryKeyError,
                 ~r|expected delete on corrupted_pk to return at most one entry but got 3 entries|,
                 fn -> TestRepo.delete!(schema) end
  end

  test "Repo.insert! escape" do
    TestRepo.insert!(%Post{title: "'"})

    query = from(p in Post, select: p.title)
    assert ["'"] == TestRepo.all(query)
  end

  test "Repo.update! escape" do
    p = TestRepo.insert!(%Post{title: "hello"})
    TestRepo.update!(Ecto.Changeset.change p, title: "'")

    query = from(p in Post, select: p.title)
    assert ["'"] == TestRepo.all(query)
  end

  test "Repo.insert_all escape" do
    TestRepo.insert_all(Post, [%{title: "'"}])

    query = from(p in Post, select: p.title)
    assert ["'"] == TestRepo.all(query)
  end

  test "Repo.update_all escape" do
    TestRepo.insert!(%Post{title: "hello"})

    TestRepo.update_all(Post, set: [title: "'"])
    reader = from(p in Post, select: p.title)
    assert ["'"] == TestRepo.all(reader)

    query = from(Post, where: "'" != "")
    TestRepo.update_all(query, set: [title: "''"])
    assert ["''"] == TestRepo.all(reader)
  end

  test "Repo.delete_all escape" do
    TestRepo.insert!(%Post{title: "hello"})
    assert [_] = TestRepo.all(Post)

    TestRepo.delete_all(from(Post, where: "'" == "'"))
    assert [] == TestRepo.all(Post)
  end

  test "load" do
    inserted_at = ~N[2016-01-01 09:00:00.000000]
    TestRepo.insert!(%Post{title: "title1", inserted_at: inserted_at, public: false})

    result = Ecto.Adapters.SQL.query!(TestRepo, "SELECT * FROM posts", [])
    posts = Enum.map(result.rows, &TestRepo.load(Post, {result.columns, &1}))
    assert [%Post{title: "title1", inserted_at: ^inserted_at, public: false}] = posts
  end
end
