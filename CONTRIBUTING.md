# How to contribute

Happy to see you are interested in helping.

We have a comprehensive documentation on how to contribute here: **[Contributing to AtlassianPS](https://atlassianps.org/docs/Contributing/)**

But here is the gist of it:

1. [fork the repository](https://docs.github.com/en/github/getting-started-with-github/fork-a-repo)
2. checking out the code:  

    ```bash
    git clone https://github.com/<YOUR_GITHUB_USER>/<PROJECT_NAME>
    cd <PROJECT_NAME>
    git checkout develop
    git checkout -b <NAME_FOR_YOUR_FEATURE>
    ```

3. open it in your favorite editor. Eg using VS Code:  

    ```bash
    code .
    ```

4. make your changes
5. run the tests  

    ```powershell
    Invoke-Build
    ```

6. commit your changes  

    ```bash
    git add .
    git commit -m "<A_MESSAGE_ABOUT_THE_CHANGES>"
    git push
    ```

7. [create a Pull Request](https://help.github.com/articles/creating-a-pull-request/)
