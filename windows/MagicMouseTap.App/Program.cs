namespace MagicMouseTap.App;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        using var app = new TrayApplication();
        Application.Run();
    }
}
